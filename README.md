# Shwouns

A Nouns DAO fork with a fundamentally different economic model: **per-Noun ERC-6551 vaults
instead of a central treasury.** Holding a Shwoun gives you a vote; financial commitment
is opt-in.

```
102 tests / 15 suites / 0 failures   |   pre-audit   |   GPL-3.0
```

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
  a snapshot is taken of every funded vault's balance. The proposal's requested funds
  are collected pro-rata across vaults, then dispatched to the proposal's targets.
- **Auction proceeds fund voter incentives, not the treasury.** 100% of winning bids
  flow to a `GovernanceRewards` contract that pays out per-proposal rewards to For/Against
  voters who hold a DAO-approved Governance Incentives NFT.

The philosophical claim: governance authority and financial commitment shouldn't be the
same thing. Holding a Shwoun makes you a voter. Funding your vault is a separate, opt-in
act of conviction.

## Status

Protocol logic is **complete and tested**. Awaiting external audit and mainnet deployment.

| | |
|---|---|
| Production contracts | 16 |
| Test suites | 15 |
| Tests passing | 102 / 102 |
| External audit | Pending — recommended firms: Spearbit, Code4rena, Cantina |
| Sepolia rehearsal | Pending |
| Mainnet | Pending audit |

## How it works

### Proposal lifecycle

```
propose          ── voting opens
   ↓
castVote(0|1|2)  ── For / Against / Abstain
   ↓
queue            ── snapshot target locked at current active-vault count
   ↓
recordSnapshot   ── paged: walks active vaults, records per-asset balances
                   (assets derived from proposal calldata — ETH from values[],
                    ERC-20s from transfer() selectors)
   ↓
collect          ── paged: each vault.pullProRata transfers its share to DAOLogic
                   shortfalls (owner withdrew between snapshot and collect) are accepted
                   and logged via ShortfallRecorded events
   ↓
finalize         ── makes target.call(s) with consolidated funds
                   retryable if a target reverts (funds stay in DAOLogic)
                   automatically allocates this proposal's voter reward pool
   ↓
voter claims     ── per-voter, GR.claimVotingReward(proposalId, giTokenId)
                   gated by approved GI NFT + For/Against vote
```

### Vault sovereignty + governance authority

The vault is owned by the current Noun holder. They can withdraw at any time, including
between a proposal's snapshot and its collect. That's the protocol design — owners are
sovereign over their own capital. A proposal can request more than will ultimately be
available; finalization works with whatever was actually drawn.

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

What we kept:

- Generic `execute(target, value, data)` via Tokenbound's executor stack
- `Permissioned` for delegated vault management (warm/cold wallet splits, council multisigs)
- Full ERC-6551 spec compliance — vaults are addressable from any ERC-6551-aware tool

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

16 production contracts across 5 layers:

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
| `ShwounsVault` | ERC-6551 implementation. Stripped Tokenbound `AccountV3` plus `pullProRata` governance hook. One per Shwoun. |
| `ShwounsVaultRegistry` | Wraps the canonical ERC-6551 registry (`0x000000006551c19487814612e58FE06813775758`). Tracks the active-set of funded vaults. Holds the locked DAOLogic reference. |

### Auction layer

| Contract | Purpose |
|---|---|
| `ShwounsAuctionHouse` | Daily auction, UUPS proxied. Winning bids → `GovernanceRewards`. No-bid Shwouns → `GovernanceRewards` (not burned). Vault auto-deployed on settle. Fork of `NounsAuctionHouseV3`. |

### Governance layer

| Contract | Purpose |
|---|---|
| `ShwounsDAOLogic` | UUPS-proxied facade. propose / vote / queue / recordSnapshot / collect / finalize. Admin + dynamic quorum + objection period + signed proposals + stuck-fund recovery. |
| `ShwounsDAOProposals` | Library where the actual proposal logic lives. Compound-style storage delegation pattern. |
| `ShwounsDAOData` | Pre-proposal candidates with on-chain feedback. Event-only design (no on-chain candidate storage to minimize surface). |

### Rewards layer

| Contract | Purpose |
|---|---|
| `GovernanceRewards` | Accumulator for auction proceeds. Allocates per-proposal voter reward pools at finalize. Handles voter claims and gas refunds for refundable votes. |
| `GovernanceIncentivesNFT` | Open paid-mint ERC-721. Mint proceeds → `GovernanceRewards`. |
| `ApprovalRegistry` | DAO-curated allowlist of GI NFT token IDs eligible for voter incentives. |

## Repository structure

```
shwouns/
├── src/
│   ├── token/           Token, Seeder, Descriptor, Art, Inflator, SVGRenderer + base ERC721
│   ├── vault/           Vault impl, Registry, Tokenbound abstracts (stripped)
│   ├── auction/         AuctionHouse (UUPS)
│   ├── governance/      DAOLogic, Proposals lib, DynamicQuorum, candidates (data/)
│   ├── rewards/         GovernanceRewards, GI NFT, ApprovalRegistry
│   ├── interfaces/      All public interfaces
│   └── libs/            Inflate, SSTORE2, NFTDescriptorV2
├── script/
│   ├── Deploy.s.sol            Full-stack deployment with circular-dep handling
│   └── CopyArtFromNouns.s.sol  Mainnet art population via SSTORE2 pointer sharing
├── test/
│   ├── unit/            Vault unit tests
│   ├── integration/     Auction, DAO lifecycle, rewards, deployment, art pipeline
│   └── mocks/           ERC6551Registry, ERC721, ERC20, WETH, Descriptor, NounsArt
├── foundry.toml
├── CLAUDE.md            Architecture reference (also for AI coding assistants)
└── README.md            (this file)
```

## Quick start

Requires [Foundry](https://book.getfoundry.sh/) (forge, cast, anvil).

```bash
forge install             # install OpenZeppelin v4.9.6 + forge-std + OZ-upgradeable v4.9.6
forge build               # ~10s
forge test                # ~30s; 102 tests across 15 suites
forge test -vvv           # with trace output
```

## Deployment

The full deployment dance — including circular dependencies, locks, and ownership
transfers — is handled by `script/Deploy.s.sol`. Mainnet runbook:

```bash
# 1. Deploy everything (set adminTarget to the EOA / multisig that will administer the DAO)
FOUNDERS_DAO=0x...  \
ADMIN_TARGET=0x...  \
  forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC --broadcast --verify

# 2. The deploy script sets adminTarget as pending admin; accept it
cast send $DAO_PROXY 'acceptAdmin()' --rpc-url $MAINNET_RPC --account ops

# 3. Populate art by sharing Nouns' SSTORE2 pointers (Nouns art is CC0)
SHWOUNS_DESCRIPTOR=$DESCRIPTOR  \
  forge script script/CopyArtFromNouns.s.sol --rpc-url $MAINNET_RPC --broadcast

# 4. Lock the art so it can't be modified
cast send $DESCRIPTOR 'lockParts()'

# 5. Unpause the auction house (kicks off the first auction)
cast send $AUCTION_HOUSE_PROXY 'unpause()'

# 6. Hand off all ownership to the DAO
cast send $DEPLOY_CONTRACT 'transferOwnershipToDAO(...)'
```

For testnet (Sepolia, etc.) deployment, Nouns Art isn't available on-chain, so the
`CopyArtFromNouns` script won't work. Re-encode from Nouns' source PNGs using the
`nouns-assets` NPM package, or skip art population if you're only testing governance
flows.

Configuration is via env vars or `Deploy.Config` struct. Defaults are documented in
`script/Deploy.s.sol`.

## What we built on

- **Nouns DAO** ([nouns-monorepo](https://github.com/nounsDAO/nouns-monorepo)) —
  the token, auction house, governance lifecycle, art rendering stack, and (via SSTORE2
  pointer sharing) the actual art content. CC0; thank you Nouners.
- **Tokenbound** ([contracts](https://github.com/tokenbound/contracts)) —
  the ERC-6551 reference implementation that the Vault forks from (stripped of features
  we didn't want).
- **OpenZeppelin Contracts v4.9.6** + **OpenZeppelin Contracts Upgradeable v4.9.6** —
  standard library.
- **ERC-6551 reference implementation** ([erc6551/reference](https://github.com/erc6551/reference)) —
  the canonical registry contract.

## What's distinct from upstream

If you're comparing against Nouns mainline, the deltas are:

- **No glasses.** Trait set drops to 4 (background, body, accessory, head). Storage and
  Descriptor surface stripped accordingly.
- **No treasury.** Per-Noun vaults plus a single accumulator (`GovernanceRewards`) for
  auction proceeds.
- **No timelock.** Proposal execution flow replaced with snapshot → collect → finalize.
- **No fork mechanism.** Doesn't apply with no central treasury.
- **No client incentives system.** Replaced with the Governance Incentives NFT model.
- **Same governance lifecycle** as Nouns V4: propose, vote, dynamic quorum, objection
  period, signed proposals, candidates. Added: stuck-fund recovery, paged snapshot,
  paged collect.

If you're comparing against Tokenbound's `AccountV3`, the vault deltas are:

- **No `Overridable`** — closes the governance-override attack.
- **No `Lockable`** — owner sovereignty makes locks redundant.
- **No `ERC4337Account`** — unused.
- **No `NestedAccountExecutor`** — not applicable.
- **No `OPAddressAliasHelper`** — cross-chain message handling not in scope.
- **Added `pullProRata`** — privileged hook callable only by the registered DAOLogic.
- **Added active-set notification** — `markActive` / `markPossiblyInactive` callbacks
  to the registry on deposit / withdraw.

## Safety notes (pre-audit)

This protocol has not been externally audited. Until it is:

- Do not deploy with real funds beyond test amounts.
- The novel mechanic (snapshot → collect → finalize across distributed vaults) hasn't
  been reviewed by a third-party security firm. Edge cases around active-set mutation
  during the snapshot phase, shortfall accumulation, and cross-vault gas dynamics
  warrant focused review.
- Vault implementations are stripped from Tokenbound's audited base. The diff is
  documented but the resulting contract is effectively new code from an audit standpoint.

## License

GPL-3.0, matching Nouns DAO. Forked artwork is CC0.

## Acknowledgements

This project is a derivative of Nouns DAO's public-good infrastructure. The proliferation
license (CC0) is the entire reason this fork is possible — both the art and the protocol
patterns. Built with the assumption that everything we ship here is also CC0/GPL-compatible
and inherits the upstream's commitment to openness.

Tokenbound's ERC-6551 work is similarly the technical foundation that makes the vault
model possible. The novel parts of Shwouns are the integration of these primitives, not
the primitives themselves.
