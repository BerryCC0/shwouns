# Shwouns Documentation — Plan & Spec

> Kickoff spec for the documentation effort. Written at the end of the round-2 audit-remediation
> session (all 5 findings fixed, on `main`) while the whole protocol was loaded in context, so the
> documentation session doesn't have to re-derive scope, priorities, or tooling. Branch: `docs`.

## Goal & audience

Thorough docs for **every contract and every function**, plus **visuals for how the contracts relate
and interact**. Primary lens: **integrators / developers** (function reference, how-to-call, events to
index, deploy runbook). Layered so it also serves **auditors** (invariants, trust boundaries, the
escrow/auth model), **contributors** (architecture + file authority + how to extend), and the
**DAO community** (a conceptual intro). One body of docs, written integrator-first, with deeper
sections the other audiences jump to.

## Approach (decided)

**Complete the NatSpec, then `forge doc` for the per-function reference**, and **hand-author** the
overview, the relationship/architecture diagrams, and the flow sequence diagrams. NatSpec is the
single regenerable source of truth (also powers IDE tooltips); hand-authored layers cover what
auto-gen can't (the novel snapshot→collect→finalize semantics, the no-treasury model, trust model).

## Deliverables / file tree (under `docs/`)

```
docs/
  README.md                      # index + reading paths per audience
  overview.md                    # what Shwouns is: no-treasury model, layers, trust model (start here)
  concepts/
    no-treasury-vaults.md        # per-Noun ERC-6551 vaults vs a central treasury (community-facing)
    voter-incentives.md          # GI NFT + allowlist + rewards (community-facing)
  architecture/
    relationships.md             # contract-relationship map + narrative (who owns/calls/references whom)
    auth-and-trust.md            # GovernanceAuthRegistry / GovernedOwnable / executor auth / no-EOA handoff
    storage-layout.md            # narrative over docs/storage-layout/*.norm.json + the __gap discipline
    diagrams/                    # generated SVGs (surya / sol2uml) + Mermaid sources
  flows/
    governance-lifecycle.md      # propose→vote→queue→recordSnapshot→collect→finalize→allocate→claim (seq diagram)
    escrow-execution.md          # per-proposal ProposalEscrow + isActiveExecutor (the novel core)
    auction-and-rewards.md       # auction→bid→settle→proceeds→GR + mint→vault
    deployment.md                # Bootstrap deploy/execute/registerManifest → finalizeBootstrap handoff
  reference/                     # forge doc OUTPUT (generated book) — set [doc] out = "docs/reference"
```

> `forge doc`'s default output is `./docs`, which would clobber the hand-authored tree. **Add to
> `foundry.toml`:** `[doc]` with `out = "docs/reference"` (and optionally `title = "Shwouns"`), so the
> generated reference lands in `docs/reference/` and the curated docs live alongside it.

## Contract inventory by doc depth (55 .sol files)

The depth differs sharply by origin — don't spend equal effort everywhere. See `CLAUDE.md` "File
authority" for the canonical origin table.

**A. Original work — DOCUMENT DEEPLY (full NatSpec on every fn + featured in flows):**
- Auction: `auction/ShwounsAuctionHouse.sol`
- Governance: `governance/ShwounsDAOLogic.sol` (facade), `ShwounsDAOProposals.sol`,
  `ShwounsDAOSignatures.sol`, `ShwounsDAOQuorum.sol` (libraries), `ShwounsDAOInterfaces.sol`
  (types/events/**storage struct** — document every field + the `__gap` discipline),
  `GovernanceAuthRegistry.sol`, `GovernedOwnable.sol`, `ProposalEscrow.sol`, `Bootstrap.sol`,
  `data/ShwounsDAOData.sol`
- Rewards: `rewards/GovernanceRewards.sol`, `GovernanceIncentivesNFT.sol`, `ApprovalRegistry.sol`
- Vault: `vault/ShwounsVault.sol`, `ShwounsVaultRegistry.sol`, `IShwounsVaultRegistry.sol`
- Scripts/libs: `script/ShwounsDeployer.sol`, `Deploy.s.sol`, `CopyArtFromNouns.s.sol`

**B. Forked Nouns, glasses removed — DOCUMENT + note the fork + the diff:**
- `token/ShwounsToken.sol`, `ShwounsDescriptor.sol`, `ShwounsSeeder.sol`, `ShwounsArt.sol`
- `interfaces/IShwouns*.sol` (Token, AuctionHouse, Descriptor, DescriptorMinimal, Seeder, Art)

**C. Forked Nouns libs / base — LIGHT (interface surface + link upstream; battle-tested, do not edit):**
- `token/Inflator.sol`, `SVGRenderer.sol`, `libs/Inflate.sol`, `NFTDescriptorV2.sol`, `SSTORE2.sol`
- `token/base/ERC721.sol`, `ERC721Checkpointable.sol`, `ERC721Enumerable.sol`
- `interfaces/IWETH.sol`, `IInflator.sol`, `ISVGRenderer.sol`, `IChainalysisSanctionsList.sol`

**D. Forked Tokenbound ERC-6551 — LIGHT (note origin + WHAT WE STRIPPED — esp. `Overridable` removal,
   the non-upgradeable impl; this is a security-relevant diff worth a callout):**
- `vault/abstract/*` (ERC6551Account, Permissioned, Signatory, execution/*),
  `vault/erc6551/*`, `vault/lib/*`, `vault/interfaces/ISandboxExecutor.sol`, `vault/utils/Errors.sol`

## NatSpec pass (the bulk of the work)

- Convention: `@title`/`@notice`/`@dev` on every contract; `@notice` (what) + `@dev` (how/why) +
  `@param`/`@return` on every external/public function; `@inheritdoc` for interface implementations to
  avoid duplication. Document custom errors and events too.
- Find gaps fast: `forge doc` renders whatever NatSpec exists — sparse pages = gaps. Also
  `forge build` with `--no-cache` surfaces missing-NatSpec nothing by default, so just scan the
  generated `docs/reference/` for thin function entries.
- Much rationale already lives in block comments from the remediation; the pass is largely
  converting/with formal `@param`/`@return` tags, not writing from scratch. Group A first.
- Preserve the `*.original` pristine references and forked-lib files per `CLAUDE.md` File authority —
  for C/D, add a top-of-file `@dev Forked from <source> @ <ref>; changes: <…>` and don't churn bodies.

## Visuals to author

Auto-generated (commit the SVGs under `docs/architecture/diagrams/`):
- **Relationship / call graph** — `surya graph src/**/*.sol | dot -Tsvg` (or `surya mdreport`).
- **Inheritance** — `surya inheritance` or `sol2uml class`.
- **Storage layout** — `sol2uml storage` for `ShwounsDAOLogic` + `ShwounsAuctionHouse` (pairs with the
  `docs/storage-layout/*.norm.json` gate).
- Install: `npm i -g surya sol2uml` (+ graphviz `dot`).

Hand-authored Mermaid (highest value — auto-tools miss the semantics):
1. **System map** — layers + ownership/reference/call edges (Token, Vault, Auction, Governance,
   Rewards, Execution, Deployment).
2. **Governance lifecycle sequence** — propose→vote→queue→recordSnapshot→collect→finalize→
   `GR.allocateProposalReward`→`claimVotingReward`.
3. **Escrow execution sequence** — finalize sets the Executing lock → `escrow.execute` runs actions
   from the per-proposal identity → governed contracts authorize via `isActiveExecutor` → terminal
   `Executed` set last. (The C-01/C-02 fix; the novel core.)
4. **Auction + rewards sequence** — bid→settle→100% proceeds→GR, no-bid→GR; mint→vault deployed.
5. **Deployment sequence** — operator→Bootstrap `deploy`/`execute`/`registerManifest`→
   `finalizeBootstrap` (bind→unpause→transfer all to DAO→setAdminToDAO→disable).
6. **ProposalState machine** — all 14 states incl. the transient `Executing` (state diagram).
7. **Reward accounting** — allocate→reserve (`totalReserved`)→claim (dual flag)→180d deadline release.

## Source-of-truth inputs (already in the repo / workspace)

- `CLAUDE.md` — architecture, layers, invariants, File authority, deploy runbook.
- Project memory (`~/.claude/.../memory/project_shwouns.md`) — full design + remediation history.
- Plan files in `~/.claude/plans/` — `what-happens-to-a-lucky-meteor.md` (original design + AVP),
  `hey-claude-we-ve-been-velvet-canyon.md` (round-1), `audit-findings-critical-deployment-reactive-bachman.md` (round-2).
- `AUDIT_REPORT.md`, `REMEDIATION_PLAN.md`, `ARCHITECTURE_REVIEW_A.md` — finding-level detail for the
  auditor-facing sections.
- `docs/storage-layout/*.norm.json` — the storage gate snapshots.

## Suggested order

1. `[doc] out = "docs/reference"` in `foundry.toml`; run `forge doc` to get the baseline + see gaps.
2. NatSpec pass, Group A → B → (light C/D). Regenerate `forge doc`.
3. `overview.md` + the system-map diagram (gives everything a spine).
4. The four `flows/` sequence diagrams (the highest-value visuals).
5. `architecture/` (relationships, auth-and-trust, storage-layout) + generated SVGs.
6. `concepts/` (community) + `README.md` reading paths.
7. Keep `main` deploy-frozen; docs work can merge independently of the Sepolia gate.
