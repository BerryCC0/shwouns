# Architecture: Contract relationships

Who owns, calls, and references whom. This complements the per-contract
[generated reference](../reference/SUMMARY.md) and the [system map](../overview.md#the-layers) with
the relationship narrative an auto-generated call graph can't fully convey. Auto-generated call/
inheritance graphs are committed under [diagrams/](diagrams/) where the tooling is available.

## Reference / call edges by layer

### Token layer
- `ShwounsToken` holds references to a `descriptor` (`IShwounsDescriptorMinimal`) and a `seeder`
  (`IShwounsSeeder`), each settable until separately locked. On mint it calls
  `seeder.generateSeed(id, descriptor)` and stores the seed; `tokenURI`/`dataURI` delegate to the
  descriptor.
- `ShwounsDescriptor` references `ShwounsArt` (trait image/palette storage) and an `ISVGRenderer`. It
  is the **only** address authorized to write `ShwounsArt` (the art's `onlyDescriptor` gate). It links
  the `NFTDescriptorV2` library for tokenURI assembly.
- `ShwounsArt` stores compressed images via `SSTORE2` and decompresses with an `IInflator`
  (`Inflator` → `Inflate`). `SVGRenderer` turns RLE bytes into SVG.
- The token's `minter` is the auction house; ownership of token/descriptor is the DAO post-handoff.

### Vault layer
- `ShwounsVaultRegistry` wraps the canonical ERC-6551 registry
  (`0x000000006551c19487814612e58FE06813775758`) to compute/deploy each Shwoun's deterministic
  `ShwounsVault`. It holds the **locked** `daoLogic` reference (vaults gate `pullProRata` on it) and
  the **locked** `vaultImplementation`.
- `ShwounsVault` references the registry immutably (baked into the impl). It reads its bound Shwoun's
  owner from `ShwounsToken` (via `ERC6551AccountLib.token()`), and notifies the registry
  (`markActive`) on deposit. The registry's active set is **append-only** ("ever funded").

### Auction layer
- `ShwounsAuctionHouse` references `ShwounsToken` (mint + transfer), the `vaultRegistry`
  (`createVaultFor` on mint/settle), and `governanceRewards` (100% of proceeds). The last two are set
  once and locked. It is a UUPS proxy; upgrades require `isActiveExecutor` (governance only).

### Governance layer
- `ShwounsDAOLogic` (UUPS facade) `delegatecall`s into `ShwounsDAOProposals` / `ShwounsDAOSignatures`
  / `ShwounsDAOQuorum` against one storage struct (`using … for Storage`). It references the
  `shwouns` token (voting power), the `vaultRegistry` (`pullProRata` + active-set enumeration), and
  `governanceRewards` (`allocateProposalReward`, `refundGas`).
- It deploys one `ProposalEscrow` clone per proposal and is the **sole driver** of every escrow.
- `GovernanceAuthRegistry` is bound once to the DAOLogic proxy and is referenced **immutably** by
  every governed contract; it forwards `isActiveExecutor` to DAOLogic, fail-closed. See
  [auth-and-trust.md](auth-and-trust.md).
- `ShwounsDAOData` is standalone (event-only candidates); it references nothing and is referenced by
  nothing on-chain (off-chain indexers reconstruct candidates from its events).

### Rewards layer
- `GovernanceRewards` references the `dao` (reads vote receipts/totals) and the `approvalRegistry`
  (eligibility), both set once and locked. It receives auction proceeds and GI mint proceeds.
- `GovernanceIncentivesNFT` forwards mint proceeds to its `proceedsRecipient` (GovernanceRewards).
- `ApprovalRegistry` references the `giNFT` (to verify ownership at claim time).

### Ownership (post-`finalizeBootstrap`)
Every `Ownable`/`GovernedOwnable` contract — token, descriptor, vault registry, rewards, GI NFT,
approval registry, auction house — is **owned by the DAO**, and `onlyOwner` is reachable only through
an authenticated proposal escrow. DAOLogic is its **own admin**. The vault implementation and the
registry/DAOLogic references are immutable or locked. See [auth-and-trust.md](auth-and-trust.md) and
[deployment.md](../flows/deployment.md).

## Forked components (origins + what we changed)

Per the File authority table in [CLAUDE.md](../../CLAUDE.md), some files are **forked verbatim or
near-verbatim** and are not edited — their behavior is battle-tested upstream and we preserve the
audit trail. They are documented here rather than re-annotated in place. (`*.original` pristine
copies are kept beside several of them for audit diffing.)

### Forked Nouns — glasses removed (Group B — editable, fully documented in the reference)
`ShwounsToken`, `ShwounsDescriptor`, `ShwounsSeeder`, `ShwounsArt` and the `IShwouns*` interfaces are
forks of `NounsToken` / `NounsDescriptorV3` / `NounsSeeder` / `NounsArt`. The **only** functional
change is removing the glasses trait: the seed has 4 traits (background, body, accessory, head); there
is no `glasses`/`glassesCount`/`addGlasses`/`updateGlasses`. `getPartsForSeed` returns 3 layered parts
(body, accessory, head) over a background. On mainnet the actual art *bytes* are reused from Nouns'
deployed `NounsArt` via SSTORE2 pointer sharing (CC0) — see [deployment.md](../flows/deployment.md).

### Forked Nouns libraries / ERC-721 base (Group C — do not edit)
Unchanged except for import-path adaptation; documented at their upstream source:
- `token/Inflator.sol`, `token/SVGRenderer.sol`, `libs/Inflate.sol`, `libs/NFTDescriptorV2.sol`,
  `libs/SSTORE2.sol` — the Nouns on-chain art rendering + storage stack.
- `token/base/ERC721.sol`, `ERC721Checkpointable.sol`, `ERC721Enumerable.sol` — the ERC-721 base with
  Compound-style vote checkpoints (the source of `getPriorVotes`/`getCurrentVotes`).
- `interfaces/IWETH.sol`, `IInflator.sol`, `ISVGRenderer.sol`, `IChainalysisSanctionsList.sol`.

### Forked Tokenbound ERC-6551 (Group D — do not edit; security-relevant diff)
`ShwounsVault` is a fork of Tokenbound's `AccountV3`. The vault impl is **non-upgradeable** (closing
the Tokenbound upgrade vector), and several `AccountV3` mixins were **stripped** — this is the most
security-relevant fork delta:

| Removed from AccountV3 | Why |
|---|---|
| **`Overridable`** | Let the NFT owner replace the implementation of any function selector — including `pullProRata`. Removing it closes the governance-override attack. **This is the key one.** |
| `Lockable` | Redundant with our "owner can always withdraw" sovereignty model. |
| `ERC4337Account` | Unused. |
| `NestedAccountExecutor` | Depends on `Lockable`; not applicable. |
| `OPAddressAliasHelper` | For cross-chain message handling we don't do. |

Added to the fork: `deposit`/`withdraw` for ETH & ERC-20, the privileged `pullProRata` hook
(callable only by the registered DAOLogic), and `markActive`/`markPossiblyInactive` registry
callbacks. The supporting `vault/abstract/*`, `vault/erc6551/*`, `vault/lib/*`,
`vault/interfaces/ISandboxExecutor.sol`, and `vault/utils/Errors.sol` are the ERC-6551 reference
implementation + Tokenbound execution mixins, kept to match spec. The L-01 bounds-check hardening in
`_isValidSignature` (a deliberate divergence from upstream) is documented inline in `ShwounsVault`.

## Diagrams

Generated structural graphs live in [diagrams/](diagrams/): a `sol2uml` **class diagram**
(`class-diagram.svg` — inheritance + associations) and a `surya` **inheritance graph**
(`inheritance.svg`). The hand-authored Mermaid **system map** in
[overview.md](../overview.md#the-layers) is the highest-value relationship view (it carries the
call/value/auth edges auto-tools can't infer); the flow sequence diagrams are under
[flows/](../flows/governance-lifecycle.md). See [diagrams/README.md](diagrams/README.md) for the
regeneration commands and notes on the call-graph / storage SVGs (env-dependent tooling).
