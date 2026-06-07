# Flow: Deployment + Bootstrap handoff

How the whole system is deployed with no permanent privileged EOA, and the operational reference for
the four deployment scripts. `forge doc` does not document `script/`, so this page is the canonical
reference for them. The trust rationale is in
[architecture/auth-and-trust.md](../architecture/auth-and-trust.md); the `Bootstrap` contract itself
has a [generated reference page](../reference/SUMMARY.md).

## The handoff model

A single persistent [`Bootstrap`](../reference/SUMMARY.md) coordinator is `msg.sender` in every
constructor, so it transiently owns/admins every contract — **no EOA ever holds a role.** The
deploying EOA is only the Bootstrap `operator` (the sole address allowed to drive it). One atomic
`finalizeBootstrap` validates the entire wiring and hands every role to the DAO, then permanently
disables itself.

```mermaid
sequenceDiagram
    autonumber
    actor Op as Operator (deployer EOA)
    participant BS as Bootstrap
    participant Sys as Deployed contracts
    participant DAO as ShwounsDAOLogic

    Op->>BS: new Bootstrap()  (operator = msg.sender)
    Note over Op,BS: Step 1 — Deploy.s.sol → ShwounsDeployer.deployAll
    loop each contract
        Op->>BS: deploy(creationCode, salt)  → CREATE2
        BS->>Sys: deployed (owner/admin = Bootstrap)
    end
    Op->>BS: execute(target, wiring calldata)  (set+lock refs)
    Op->>BS: registerManifest(m)  (commit the exact address set)
    Note over Op,BS: Step 2 — CopyArtFromNouns.s.sol
    Op->>BS: executeBatch(descriptor, art-load ops)
    Note over Op,BS: Step 3 — lock art
    Op->>BS: execute(descriptor, lockParts())
    Note over Op,DAO: Step 4 — finalizeBootstrap (atomic)
    Op->>BS: finalizeBootstrap()
    BS->>BS: check ownership + locks + wiring + immutable matrix
    BS->>DAO: bindDAOLogic(dao) on the auth registry
    BS->>Sys: unpause auction (kicks off auction #1)
    BS->>Sys: transferOwnership(dao) for every Ownable
    BS->>DAO: setAdminToDAO()
    BS->>BS: assert handoff complete; finalized = true (permanent)
```

**Why finalize is a separate step from deploy:** `finalizeBootstrap` unpauses the auction, which
mints the genesis Shwoun(s); the seeder computes each trait as `pseudorandom % traitCount`, so with
zero trait counts that reverts (division by zero). Art must therefore be loaded **and locked** before
finalize.

**Why the auction is unpaused *during* the handoff (before ownership transfers):** post-handoff,
unpausing would require voting power that only auctions mint — a deadlock. So Bootstrap kicks off
auction #1 while it still owns the auction house.

## Mainnet runbook

```bash
# 1. Deploy + wire everything via Bootstrap (deploy-only: paused, all roles with Bootstrap).
#    Note the Bootstrap address (b) and descriptor (m.descriptor) from the run output.
FOUNDERS_DAO=0x...  \
  forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC --broadcast --verify

# 2. Copy Nouns art via SSTORE2 pointer sharing (~$50), routed through Bootstrap (it owns the
#    descriptor). One executeBatch transaction.
SHWOUNS_BOOTSTRAP=$BOOTSTRAP  SHWOUNS_DESCRIPTOR=$DESCRIPTOR  \
  forge script script/CopyArtFromNouns.s.sol --rpc-url $MAINNET_RPC --broadcast

# 3. Lock parts when art is final (operator → Bootstrap → descriptor).
cast send $BOOTSTRAP 'execute(address,bytes)' $DESCRIPTOR $(cast calldata 'lockParts()')

# 4. One-shot atomic handoff. Reverts if any precheck fails (never a silent bad handoff).
cast send $BOOTSTRAP finalizeBootstrap
```

Rehearse the whole runbook locally first: `./script/rehearse-deploy.sh` (anvil + minimal art).

> **Build first.** `Bootstrap`/`ShwounsDeployer` embed no creation code; `ShwounsDeployer` reads each
> contract's creation bytecode from `out/` at runtime (`vm.getCode` + library link-patching), so the
> artifacts must exist (`forge build`).

## Script operational reference

`forge doc` skips `script/`. The four scripts and two shell helpers:

### `script/ShwounsDeployer.sol` (library)

The single source of truth for "deploy + wire the whole system via Bootstrap," shared by the
broadcast script **and** the integration tests (so tests exercise the exact on-chain path).

- **Entry point:** `deployAll(Bootstrap b, Config cfg) internal returns (DeploymentManifest m)`. It
  is a library with `internal` functions, so calls inline into the caller — every
  `b.deploy/execute/registerManifest` has the caller (the trusted operator) as `msg.sender`,
  satisfying Bootstrap's `onlyOperator` gate.
- **What it does:** deploys, in dependency order — auth registry → art stack (NFTDescriptorV2,
  Inflator, SVGRenderer, ShwounsArt, ShwounsDescriptor) → token + seeder → vault registry + impl →
  rewards + GI NFT + approval registry → auction house (UUPS) → DAOLogic (libs + linked impl + UUPS)
  → ProposalEscrow impl → candidates registry. It sets and locks every one-time reference, then
  `registerManifest`. Leaves the system **paused with Bootstrap holding every role** (pre-finalize).
- **Library link-patching:** contracts that link external libraries (`ShwounsDescriptor` →
  `NFTDescriptorV2`; `ShwounsDAOSignatures` → `ShwounsDAOProposals`; the DAOLogic impl → all three
  governance libs) can't be read by `vm.getCode`, so `_linkedInitcode` reads the artifact's
  `bytecode.object`, replaces each `__$<34hex>$__` placeholder with the deployed library address,
  asserts none remain, then parses. The placeholder is `keccak256("src/path.sol:Name")[0:34 hex]`.
- **`Config` struct:** all deployment parameters (founders DAO, WETH, auction knobs, governance
  params, GI mint price, reward amounts). Not for direct external use.

### `script/Deploy.s.sol` (broadcast wrapper — Step 1)

- **Entry point:** `run() returns (Bootstrap b, DeploymentManifest m)`. Deploys one `Bootstrap`, then
  `ShwounsDeployer.deployAll(b, defaultConfig())` inside a `vm.startBroadcast()`.
- **Config via env vars** (with mainnet-sane defaults), e.g. `FOUNDERS_DAO` (default `tx.origin`),
  `WETH_ADDRESS` (default canonical mainnet WETH), `AUCTION_DURATION_SEC` (86400), `RESERVE_PRICE_WEI`
  (0.01 ETH), `VOTING_DELAY_BLOCKS` (7200), `VOTING_PERIOD_BLOCKS` (36000), `PROPOSAL_THRESHOLD_BPS`
  (25), `QUORUM_VOTES_BPS` (1000), `GI_MINT_PRICE_WEI` (0.01 ETH), `PROPOSAL_REWARD_WEI` (0.1 ETH),
  `MAX_REFUND_PER_VOTE_WEI` (0.003 ETH), `LAST_MINUTE_WINDOW_BLOCKS` (1200), `OBJECTION_PERIOD_BLOCKS`
  (7200). See `defaultConfig()` for the full list.
- **Output:** the Bootstrap address and the manifest (incl. `m.descriptor`) — needed for steps 2–4.

### `script/CopyArtFromNouns.s.sol` (Step 2 — mainnet only)

- **Entry point:** `run()` reads `SHWOUNS_BOOTSTRAP` + `SHWOUNS_DESCRIPTOR` (and optional `NOUNS_ART`,
  default `0x6544bC8A0dE6ECe429F14840BA74611cA5098A92`) and calls `copy(...)`.
- **What it does:** Nouns art is CC0 and stored at SSTORE2 pointers (just bytecode), so it **reuses
  the same pointers** rather than re-uploading the bytes — recording them into ShwounsArt via the
  descriptor's `setPalettePointer` / `addManyBackgrounds` / `add*FromPointer`. Glasses are skipped.
  Every descriptor op is routed through `bootstrap.executeBatch` (the descriptor is Bootstrap-owned
  during deployment — audit F3). One batched tx, ~2–3M gas (under $50).
- **Constraint:** only works on mainnet or a mainnet fork (where Nouns Art exists). For testnets,
  re-encode real art from Nouns' source PNGs, or load placeholder art (as `RehearseDeploy` does).

### `script/RehearseDeploy.s.sol` (local dress rehearsal)

- **Entry point:** `run() returns (Bootstrap b, DeploymentManifest m)`. Runs the **whole runbook in
  one broadcast** — deploy → load minimal placeholder art → `lockParts` → `finalizeBootstrap` —
  exercising CREATE2, link-patching, the operator gate, and the atomic handoff as real transactions.
- **Why:** a `forge script` *simulation* passed a prior round yet the system was undeployable; this
  catches that by broadcasting against a local anvil with the canonical ERC-6551 registry etched.
- **Placeholder art:** loads one trivial background/body/accessory/head + `lockParts` (trait counts
  come from the explicit `imageCount`, so trivial bytes suffice) so the genesis mint works. **Not for
  mainnet** — mainnet uses `CopyArtFromNouns`.
- **Post-asserts** every handoff invariant (token/registry owned by DAO, DAO admin = DAO, registry
  bound, auction unpaused with genesis auction #1 live).

### Shell helpers

- **`script/rehearse-deploy.sh`** — spins up anvil, etches the canonical ERC-6551 registry, and runs
  `RehearseDeploy.s.sol --broadcast`. The deployability gate (41 txs broadcast cleanly).
- **`script/check-storage-layout.sh`** — the nested-aware storage-layout drift gate for the two UUPS
  proxies. See [architecture/storage-layout.md](../architecture/storage-layout.md).

## Testnet (Sepolia) note

Nouns Art isn't on testnets, so `CopyArtFromNouns` won't work, and **art cannot be skipped if you
intend to finalize** (finalize → unpause → genesis mint → seeder needs non-zero trait counts).
Either re-encode real art from Nouns' source PNGs and load it via `bootstrap.executeBatch`, or load
placeholder art exactly as `RehearseDeploy` does, then finalize.
