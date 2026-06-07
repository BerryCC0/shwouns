# Shwouns

A Nouns DAO fork with a fundamentally different economic model: **per-Noun ERC-6551 vaults
instead of a central treasury.** Holding a Shwoun gives you a vote; financial commitment
is opt-in.

```
212 tests / 26 suites / 0 failures   |   2 internal audit rounds remediated   |   GPL-3.0
```

> **Do not deploy yet.** Two internal security-review rounds have been remediated and a focused
> re-review of the deploy/refund changes cleared. A Sepolia dress rehearsal + the production
> art-loading path are the remaining gates before mainnet; an external audit is still recommended.

---

## The idea

Standard Nouns concentrates capital in one place (the treasury timelock) and distributes
governance authority (one Noun = one vote). Proposals execute by drawing on the treasury.

Shwouns inverts the capital model:

- **No central treasury.** Each Shwoun is bound to an ERC-6551 [token-bound account](https://eips.ethereum.org/EIPS/eip-6551) — a smart contract account owned by the current
  holder. That account is the "Vault." Owners deposit and withdraw ETH and ERC-20s at
  will. They can delegate management to a warm/cold-split wallet, a council multisig, or
  a yield manager via the Tokenbound `Permissioned` pattern.
- **Governance pulls pro-rata from active vaults at execution.** When a proposal passes,
  a snapshot is taken of every funded vault's balance. The proposal's requested funds are
  collected pro-rata across vaults into a **per-proposal escrow**, which then executes the
  proposal's actions from its own isolated identity.
- **Auction proceeds fund voter incentives, not the treasury.** 100% of winning bids
  flow to a `GovernanceRewards` contract that pays out per-proposal rewards to For/Against
  voters who hold a DAO-approved Governance Incentives NFT.

The philosophical claim: governance authority and financial commitment shouldn't be the
same thing. Holding a Shwoun makes you a voter. Funding your vault is a separate, opt-in
act of conviction.

## Status

Protocol logic is **complete, tested, and twice-remediated**. Remaining before mainnet: a
Sepolia dress rehearsal, verification of the production art-loading path, and (recommended)
an external audit.

| | |
|---|---|
| Production contracts | 18 |
| Test suites | 26 |
| Tests passing | 212 / 212 |
| EIP-170 | Every contract < 24,576 bytes (`forge build --sizes`) |
| Internal review | 2 rounds remediated (14 + 5 findings); focused re-review of deploy/refund cleared |
| External audit | Recommended — Spearbit, Code4rena, Cantina |
| Sepolia rehearsal | Next gate (anvil `--broadcast` rehearsal passes locally) |
| Mainnet | Frozen until Sepolia + art path verified |

## How it works

### Proposal lifecycle

```
propose          ── voting opens (Updatable window → Pending → Active → ObjectionPeriod)
   ↓
castVote(0|1|2)  ── For / Against / Abstain  (refundable variants route gas through GR)
   ↓
queue            ── freezes the active-vault SET (paged) + deploys this proposal's escrow (CREATE2)
   ↓
recordSnapshot   ── paged: walks the frozen vault set, records per-asset balances
                   (assets derived from proposal calldata — ETH from values[],
                    allowlisted ERC-20s from transfer() selectors)
   ↓
collect          ── paged: each vault.pullProRata transfers its share INTO the proposal's escrow
                   shortfalls (owner withdrew between snapshot and collect) are accepted + logged
   ↓
finalize         ── the escrow executes the proposal's actions from its OWN isolated balance
                   all-or-nothing solvency check; retryable if a target reverts; sets terminal state
                   automatically allocates this proposal's voter reward pool
   ↓
voter claims     ── per-voter, GR.claimVotingReward(proposalId, giTokenId)
                   gated by approved GI NFT + For/Against vote
```

Funded-but-dead proposals (Canceled / Vetoed) and stuck Collected proposals return each vault's
**actual** contribution to **that vault** via the paged `refund` / `refundStuckProposal` paths.

### Per-proposal escrow + executor authentication

Each proposal gets its own single-use [`ProposalEscrow`](src/governance/ProposalEscrow.sol) —
a deterministic EIP-1167 clone deployed at `queue`. Collected funds land in the escrow, and
**all** of the proposal's actions (value-bearing and governance) execute from that escrow's unique
identity. DAO-owned contracts authorize a caller only when DAOLogic vouches that it is the
currently-executing proposal's escrow (`isActiveExecutor`: deterministic address + clone codehash +
transient execution lock). This isolates each proposal's assets and closes cross-proposal
fund-drain and reentrancy vectors by construction, rather than by bookkeeping in a shared wallet.

### Vault sovereignty + governance authority

The vault is owned by the current Noun holder. They can withdraw at any time, including
between a proposal's snapshot and its collect. That's the protocol design — owners are
sovereign over their own capital. A proposal can request more than will ultimately be
available; finalization is all-or-nothing against what the escrow actually holds (top up the
shortfall, or unwind via refund).

The DAOLogic is the **only** caller authorized to invoke `vault.pullProRata`. This is
enforced at the vault level via `vaultRegistry.daoLogic()`, locked at deployment.

### Vault as a working capital vehicle

Each vault is a full ERC-6551 account with generic `execute(target, value, data)`. The
owner can put vault assets to work in DeFi (lending, LP, etc.) directly from the vault,
or delegate that to another address via `Permissioned`. Bridges work normally too —
the vault can hold cross-chain positions and recall them via standard bridge contracts.

What we stripped from Tokenbound's `AccountV3` to harden the governance integration:

- **`Overridable`** — let the NFT owner replace the implementation of any function
  selector. Removing this closes the governance-override attack (where a holder could
  override `pullProRata` to do nothing).
- **`Lockable`** — redundant with our "owner can always withdraw" sovereignty model.
- **`ERC4337Account`** — unused.
- **`NestedAccountExecutor`** — depends on `Lockable`; not applicable to our model.
- **`OPAddressAliasHelper`** — for cross-chain message handling we don't do.

The vault implementation is also **non-upgradeable** (closing the Tokenbound upgrade vector).

### Governance Incentives NFT

Voter rewards need an anti-sybil layer. We use a two-stage gate:

1. **Open paid mint.** Anyone can mint a Governance Incentives NFT for the configured
   price (0.01 ETH default). Mint proceeds flow to `GovernanceRewards`.
2. **DAO-controlled allowlist.** The DAO approves specific GI NFT token IDs via
   governance proposal. Only approved token IDs make their holder eligible to claim voter
   incentives.

Approval is keyed by `tokenId`, not by holder address. If an approved GI NFT is sold or
transferred, the approval follows it. This is intentional — the DAO is approving an
auditable on-chain identity, not a wallet that can hop ownership.

For/Against voters earn pro-rata of the proposal's reward pool (0.1 ETH default).
Abstain voters don't earn.

## Architecture

Production contracts grouped into six layers, plus a deployment coordinator. (`via_ir = true`, and
the governance library is split into three so the facade + each library fit under EIP-170 — hot
paths stay same-library JUMPs.)

### Token layer

| Contract | Purpose |
|---|---|
| `ShwounsToken` | ERC-721 with vote delegation (Compound-style checkpoints). Auctioned daily, every 10th to founders for the first 1820. |
| `ShwounsSeeder` | Deterministic 4-trait seed generator (background, body, accessory, head — no glasses). |
| `ShwounsDescriptor` | Renders tokenURI from seed; admin-controlled trait additions. Fork of `NounsDescriptorV3`. |
| `ShwounsArt` | On-chain SSTORE2 storage for compressed image data. Fork of `NounsArt`. |
| `Inflator` | Deflate decompression. Unchanged from Nouns. |
| `SVGRenderer` | RLE → SVG conversion. Unchanged from Nouns. |

### Vault layer

| Contract | Purpose |
|---|---|
| `ShwounsVault` | ERC-6551 implementation (non-upgradeable). Stripped Tokenbound `AccountV3` plus the `pullProRata` governance hook. One per Shwoun. |
| `ShwounsVaultRegistry` | Wraps the canonical ERC-6551 registry (`0x000000006551c19487814612e58FE06813775758`). Tracks the append-only active set of funded vaults. Holds the locked DAOLogic reference. |

### Auction layer

| Contract | Purpose |
|---|---|
| `ShwounsAuctionHouse` | Daily auction, UUPS proxied. Winning bids → `GovernanceRewards`. No-bid Shwouns → `GovernanceRewards` (not burned). Vault auto-deployed on settle. Fork of `NounsAuctionHouseV3`. |

### Governance layer

| Contract | Purpose |
|---|---|
| `ShwounsDAOLogic` | UUPS-proxied facade. propose / vote / queue / recordSnapshot / collect / finalize, admin, dynamic quorum, objection period, signed proposals, stuck-fund recovery. |
| `ShwounsDAOProposals` | Library: the hot lifecycle (propose/vote/state, queue→collect→finalize, dynamic-quorum compute). |
| `ShwounsDAOSignatures` | Library: EIP-712 signed proposals (`proposeBySigs`) + proposal editing (the Updatable window). |
| `ShwounsDAOQuorum` | Library: dynamic-quorum checkpoint administration. |
| `GovernanceAuthRegistry` | Fail-closed registry binding the canonical DAOLogic once; governed contracts reference it immutably. |
| `GovernedOwnable` | Ownable adapter restricting ownership/admin to the DAO (or zero) + authorizing the active executor. |
| `ShwounsDAOData` | Pre-proposal candidates with on-chain feedback (event-only design). |

### Rewards layer

| Contract | Purpose |
|---|---|
| `GovernanceRewards` | Accumulator for auction proceeds. Reserves + allocates per-proposal voter reward pools at finalize; handles claims, deadlines, and gas refunds. |
| `GovernanceIncentivesNFT` | Open paid-mint ERC-721. Mint proceeds → `GovernanceRewards`. |
| `ApprovalRegistry` | DAO-curated allowlist of GI NFT token IDs eligible for voter incentives. |

### Execution layer

| Contract | Purpose |
|---|---|
| `ProposalEscrow` | Per-proposal single-use EIP-1167 clone. Holds only its proposal's collected funds and executes all its actions from an isolated identity. |

### Deployment coordinator (not a permanent role-holder)

| Contract | Purpose |
|---|---|
| `Bootstrap` | Generic operator-gated CREATE2 coordinator. Deploys + wires the system (holding all roles transiently), then a one-shot `finalizeBootstrap` atomically hands every role to the DAO and permanently disables itself. Embeds no creation code. |

## Repository structure

```
shwouns/
├── src/
│   ├── token/           Token, Seeder, Descriptor, Art, Inflator, SVGRenderer + base ERC721
│   ├── vault/           Vault impl, Registry, Tokenbound abstracts (stripped), ERC-6551 reference
│   ├── auction/         AuctionHouse (UUPS)
│   ├── governance/      DAOLogic facade + Proposals/Signatures/Quorum libs, AuthRegistry,
│   │                    GovernedOwnable, ProposalEscrow, Bootstrap, candidates (data/)
│   ├── rewards/         GovernanceRewards, GI NFT, ApprovalRegistry
│   ├── interfaces/      All public interfaces
│   └── libs/            Inflate, SSTORE2, NFTDescriptorV2
├── script/
│   ├── ShwounsDeployer.sol        Shared deploy orchestration (vm.getCode + library link-patching)
│   ├── Deploy.s.sol               Broadcast wrapper around ShwounsDeployer
│   ├── CopyArtFromNouns.s.sol     Mainnet art population via SSTORE2 pointer sharing (through Bootstrap)
│   ├── RehearseDeploy.s.sol       Full deploy+art+finalize rehearsal (anvil)
│   ├── rehearse-deploy.sh         Anvil --broadcast deployability gate
│   ├── check-storage-layout.sh    Nested storage-layout drift gate
│   └── normalize-storage-layout.py
├── test/
│   ├── unit/            Vault unit tests
│   ├── integration/     Auction, DAO lifecycle, rewards, deployment, art pipeline, execution model
│   ├── audit/           Audit-finding regression suite (PoCs flipped to assert safe behavior)
│   └── mocks/           ERC6551Registry, ERC721/1155/20, WETH, Descriptor, NounsArt
├── docs/                Storage-layout snapshots + documentation (in progress)
├── foundry.toml
├── CLAUDE.md            Architecture reference (authoritative; also for AI coding assistants)
└── README.md            (this file)
```

## Quick start

Requires [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil).

```bash
forge install                      # OpenZeppelin v4.9.6 + forge-std + OZ-upgradeable v4.9.6
forge build --sizes                # via_ir; verify every contract < 24,576 bytes (EIP-170)
forge test                         # 212 tests across 26 suites
./script/check-storage-layout.sh   # storage-layout drift gate
./script/rehearse-deploy.sh        # anvil --broadcast full deploy rehearsal
```

> `via_ir = true` is required (the governance facade doesn't fit EIP-170 otherwise). Always use
> `forge build --sizes` — plain `forge build` does not enforce the size limit.

## Deployment

The deployer EOA becomes the `Bootstrap` **operator** (the only address that can drive it). All
protocol roles are held by the persistent Bootstrap until `finalizeBootstrap`, then atomically
handed to the DAO — no permanent EOA ever owns a role. Bootstrap embeds no creation code;
`ShwounsDeployer` reads it from the built artifacts (`vm.getCode` + library link-patching), so
**build first**. Rehearse locally before any live run: `./script/rehearse-deploy.sh`.

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

# 4. One-shot atomic handoff: validates all wiring/locks/immutables, binds the registry, unpauses
#    (kicks off auction #1), transfers every Ownable to the DAO, sets DAO admin. Reverts if any
#    precheck fails. Permanently disables Bootstrap.
cast send $BOOTSTRAP finalizeBootstrap
```

For testnet (Sepolia, etc.) deployment, Nouns Art isn't available on-chain, so the
`CopyArtFromNouns` script won't work. Re-encode from Nouns' source PNGs using the
`nouns-assets` NPM package, or skip art population if you're only testing governance/auction
flows. Configuration is via env vars; defaults are in `script/Deploy.s.sol`.

## What we built on

- **Nouns DAO** ([nouns-monorepo](https://github.com/nounsDAO/nouns-monorepo)) —
  the token, auction house, governance lifecycle, art rendering stack, and (via SSTORE2
  pointer sharing) the actual art content. CC0; thank you Nouners.
- **Tokenbound** ([contracts](https://github.com/tokenbound/contracts)) —
  the ERC-6551 reference implementation that the Vault forks from (stripped of features
  we didn't want).
- **OpenZeppelin Contracts v4.9.6** + **OpenZeppelin Contracts Upgradeable v4.9.6**.
- **ERC-6551 reference implementation** ([erc6551/reference](https://github.com/erc6551/reference)) —
  the canonical registry contract.

## What's distinct from upstream

If you're comparing against Nouns mainline, the deltas are:

- **No glasses.** Trait set drops to 4 (background, body, accessory, head).
- **No treasury.** Per-Noun vaults plus a single accumulator (`GovernanceRewards`) for
  auction proceeds.
- **No timelock.** Proposal execution replaced with snapshot → collect → finalize, executed
  from a per-proposal escrow.
- **No fork mechanism.** Doesn't apply with no central treasury.
- **No client incentives system.** Replaced with the Governance Incentives NFT model.
- **Same governance lifecycle** as Nouns V4: propose, vote, dynamic quorum, objection
  period, signed proposals, candidates. Added: per-proposal escrow execution, paged
  snapshot/collect/freeze, contribution refunds, stuck-fund recovery.

If you're comparing against Tokenbound's `AccountV3`, the vault deltas are:

- **No `Overridable`** — closes the governance-override attack.
- **No `Lockable` / `ERC4337Account` / `NestedAccountExecutor` / `OPAddressAliasHelper`.**
- **Non-upgradeable** implementation.
- **Added `pullProRata`** — privileged hook callable only by the registered DAOLogic.
- **Added active-set notification** — `markActive` / `markPossiblyInactive` callbacks
  to the registry on deposit / withdraw.

## Safety notes

This protocol has **not** been externally audited and is **not deployed**. Two internal
security-review rounds (14 then 5 findings) have been remediated, with a focused re-review of the
deployment-coordinator rewrite and the refund-recipient change cleared. Until an external audit and
a successful Sepolia dress rehearsal:

- Do not deploy with real funds.
- The novel mechanic (snapshot → collect → finalize across distributed vaults, executed from a
  per-proposal escrow) is new code from an audit standpoint and warrants a third-party review.
- Vault implementations are stripped from Tokenbound's audited base; the diff is documented but the
  resulting contract is effectively new code.

## License

GPL-3.0, matching Nouns DAO. Forked artwork is CC0.

## Acknowledgements

This project is a derivative of Nouns DAO's public-good infrastructure. The proliferation
license (CC0) is the entire reason this fork is possible — both the art and the protocol
patterns. Tokenbound's ERC-6551 work is similarly the technical foundation that makes the vault
model possible. The novel parts of Shwouns are the integration of these primitives, not the
primitives themselves.
