# Shwouns — Nouns DAO fork with distributed vaults

Ethereum mainnet Nouns-style DAO with a fundamentally different economic model: per-Noun
ERC-6551 vaults instead of a central treasury. Built from `nouns-monorepo @ main` plus
Tokenbound's ERC-6551 stack.

## What's distinctive vs mainline Nouns

- **No central treasury.** Each Shwoun gets an ERC-6551 token-bound account ("Vault") on
  mint, owned by the current holder. Vault owner can deposit/withdraw ETH or any ERC-20
  at will. The vault can also act as a smart-contract wallet for DeFi (yield strategies,
  bridges) via the `Permissioned` delegation pattern.
- **Governor pulls pro-rata from vaults at execution**, not from a timelock. Snapshot
  happens at queue (after vote passes). Caller withdraws during queue→execute reduce
  the proposal's funding. Shortfalls are accepted.
- **Auction proceeds fund voter incentives**, not the treasury. 100% of winning bid →
  `GovernanceRewards` contract. No-bid Shwouns mint to `GovernanceRewards` (not burned,
  not treasury-routed).
- **Governance Incentives NFT** (open paid mint, 0.01 ETH default) + DAO-approved
  allowlist gates who can earn voting incentives. For/Against votes earn rewards; Abstain
  does not. Refundable votes route gas refunds through GR.
- **Art = Nouns without noggles.** Fork of `NounsDescriptorV3` strips the glasses trait.
  Seeder generates 4-trait seeds (background, body, accessory, head). On mainnet deploy,
  art bytes are reused from Nouns' deployed `NounsArt` via SSTORE2 pointer sharing —
  cheap (~$50 in gas), CC0-clean.

## Architecture (16 production contracts)

```
Token layer:        ShwounsToken, ShwounsSeeder, ShwounsDescriptor, ShwounsArt,
                    Inflator, SVGRenderer
Vault layer:        ShwounsVault (ERC-6551 impl), ShwounsVaultRegistry (active-set + DAO ref)
Auction layer:      ShwounsAuctionHouse (UUPS proxy, V3-fork)
Governance layer:   ShwounsDAOLogic (UUPS facade), ShwounsDAOProposals (library),
                    ShwounsDAOData (candidates)
Rewards layer:      GovernanceRewards, GovernanceIncentivesNFT, ApprovalRegistry
Deployment helper:  Deploy.s.sol, CopyArtFromNouns.s.sol
```

## Proposal lifecycle (the novel mechanic)

```
propose → vote → queue
                   ↓
            recordSnapshot(proposalId, batchSize)    [paged across active vaults]
                   ↓
            collect(proposalId, vaultIds[])           [paged; pulls pro-rata to DAOLogic]
                   ↓
            finalize(proposalId)                      [one-shot; makes target.call(s)]
                   ↓
            GR.allocateProposalReward(proposalId)     [auto-called inside finalize]
                   ↓
            voter.claimVotingReward(pid, giTokenId)   [lazy, per-voter claim]
```

For/Against voters with an approved Governance Incentives NFT claim a pro-rata share
of the proposal's reward pool (0.1 ETH default). Abstain voters don't earn.

## Key invariants

- **`ShwounsVault.pullProRata` is callable ONLY by the currently-registered DAOLogic.**
  Looked up via `vaultRegistry.daoLogic()` (locked once at deployment).
- **Vault impl is non-upgradeable** (deliberate — closes the Tokenbound upgrade vector).
  Implementation address pinned in `VaultRegistry.vaultImplementation` (locked).
- **Vaults must never use `Overridable`** — that was Tokenbound's feature where a Noun
  owner could override any function selector, including `pullProRata`. We stripped it.
- **DAOLogic.execute is replaced** — no timelock. Funds flow via snapshot→collect→finalize.
- **`finalize()` is retryable** — if `target.call` reverts, funds stay in DAOLogic; caller
  can re-run finalize after conditions change. Stuck-fund recovery via `refundStuckProposal`.
- **GI NFT eligibility is tokenId-keyed**, not address-keyed. Approval follows the NFT
  on transfer. This is intentional — DAO approves a specific (auditable) identity-bound
  asset.

## Deployment

```bash
# Mainnet
FOUNDERS_DAO=0x...  ADMIN_TARGET=0x...  \
  forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC --broadcast --verify

# Then accept DAO admin
cast send $DAO acceptAdmin

# Copy Nouns art via SSTORE2 pointer sharing (~$50 in gas)
SHWOUNS_DESCRIPTOR=$DESCRIPTOR  \
  forge script script/CopyArtFromNouns.s.sol --rpc-url $MAINNET_RPC --broadcast

# Lock parts when art is final
cast send $DESCRIPTOR lockParts

# Unpause auction (kicks off first auction)
cast send $AUCTION_HOUSE unpause

# Hand off all ownership to DAO
cast send $DEPLOY_CONTRACT 'transferOwnershipToDAO(...)'
```

For **testnet** (Sepolia, etc.) deployments, Nouns Art isn't deployed there, so
`CopyArtFromNouns` won't work. Options:
- Re-encode and re-upload from Nouns' source PNGs using the `nouns-assets` NPM package
- Skip art entirely for testnet (token URIs will revert; that's fine if you're testing
  governance/auction flows only)

## Build & test

```bash
forge build       # ~10 sec
forge test        # ~30 sec; 102 tests across 15 suites
forge test -vvv   # with trace output
```

Forge is at `~/.foundry/bin/forge` (may or may not be in PATH depending on session env;
user-level `~/.claude/settings.json` adds it to PATH for future Claude Code sessions).

## File authority

| Files | Source | Safe to edit? |
|-------|--------|--------------|
| `src/vault/abstract/*`, `src/vault/lib/*` | Forked Tokenbound — pristine copies | Only with care; original audit trail value |
| `src/vault/erc6551/*` | ERC-6551 reference impl | No — match spec exactly |
| `src/libs/Inflate.sol`, `SSTORE2.sol`, `NFTDescriptorV2.sol` | Forked Nouns libs | No — battle-tested |
| `src/token/SVGRenderer.sol`, `Inflator.sol` | Forked Nouns | No (only `import` paths adapted) |
| `src/token/ShwounsArt.sol`, `ShwounsDescriptor.sol`, `ShwounsSeeder.sol`, `ShwounsToken.sol` | Forked Nouns — glasses removed | Yes |
| `src/auction/*`, `src/governance/*`, `src/rewards/*` | Original work | Yes |
| `*.original` files (in src/) | Pristine upstream references | No — used for audit diff comparison |
| `script/*.s.sol` | Deployment + ops scripts | Yes |
| `test/*` | Test suites | Yes |

## Plan + AVP record

The full architecture decisions + AVP verification trail is at
`~/.claude/plans/what-happens-to-a-lucky-meteor.md`. That file is the source of truth
for design rationale — read it before making non-obvious changes.

## What's NOT done

- **External audit** — recommended firms: Spearbit, Code4rena, Cantina. Budget $5-15k,
  2-4 weeks lead time. Snapshot+collect+finalize mechanic is novel and warrants focused
  review.
- **Sepolia dress rehearsal** — script is runnable but never tested end-to-end on a
  real RPC. Worth doing before mainnet.
- **Production deploy** — half a day once audit feedback is incorporated.
- **Brand call** — token name/symbol use "Shwouns"/"SHWN". Final branding (logo, site,
  social handles) is product-side work, not protocol.
