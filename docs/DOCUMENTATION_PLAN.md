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

### Publication model (decided)

**Two explicitly cross-linked documentation sets — NOT one auto-merged book:**
1. **Curated docs** (`docs/overview.md`, `concepts/`, `architecture/`, `flows/`) — plain
   GitHub-rendered Markdown with Mermaid. This is the **primary** entry point; `docs/README.md`
   is its index with per-audience reading paths. No build step.
2. **Generated reference** (`docs/reference/`) — the `forge doc` mdBook (its own `SUMMARY.md`,
   `src/`-only). This is the **API reference**, linked FROM the curated docs (and its homepage links
   back). The curated pages will NOT appear in the generated book's nav and vice-versa — that's
   expected; they cross-link, they don't merge.

> **`forge doc` config (do this before the first generated output):** its default output is `./docs`,
> which would clobber the curated tree, and it copies the **root `README.md` as the book homepage**.
> Add to `foundry.toml` a `[doc]` section with `out = "docs/reference"` (and optionally
> `title = "Shwouns"`). The root `README.md` is the generated homepage, so it MUST stay current — it
> was refreshed in this branch (Bootstrap runbook, 212 tests, post-remediation status); keep it in
> sync, or set `[doc] homepage` to a dedicated reference-intro page instead.

## Contract inventory by doc depth (59 .sol files: 55 `src/` + 4 `script/`)

The depth differs sharply by origin — don't spend equal effort everywhere. See `CLAUDE.md` "File
authority" for the canonical origin table.

> **`forge doc` only documents `src/`** — the four `script/` files get NO generated reference. They
> must be hand-authored as an **operational reference** page (`flows/deployment.md` covers the runbook;
> add a short per-script section: purpose, entrypoints, env vars, what it deploys/drives). All four are
> in scope: `ShwounsDeployer.sol`, `Deploy.s.sol`, `CopyArtFromNouns.s.sol`, `RehearseDeploy.s.sol`.

**A. Original work — DOCUMENT DEEPLY (full NatSpec on every fn + featured in flows):**
- Auction: `auction/ShwounsAuctionHouse.sol`
- Governance: `governance/ShwounsDAOLogic.sol` (facade), `ShwounsDAOProposals.sol`,
  `ShwounsDAOSignatures.sol`, `ShwounsDAOQuorum.sol` (libraries), `ShwounsDAOInterfaces.sol`
  (types/events/**storage struct** — document every field + the `__gap` discipline),
  `GovernanceAuthRegistry.sol`, `GovernedOwnable.sol`, `ProposalEscrow.sol`, `Bootstrap.sol`,
  `data/ShwounsDAOData.sol`
- Rewards: `rewards/GovernanceRewards.sol`, `GovernanceIncentivesNFT.sol`, `ApprovalRegistry.sol`
- Vault: `vault/ShwounsVault.sol`, `ShwounsVaultRegistry.sol`, `IShwounsVaultRegistry.sol`
- Scripts (hand-authored operational reference — `forge doc` skips `script/`):
  `script/ShwounsDeployer.sol`, `Deploy.s.sol`, `CopyArtFromNouns.s.sol`, `RehearseDeploy.s.sol`

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
  converting/with formal `@param`/`@return` tags, not writing from scratch. Group A first, then B.
- **Respect File authority (`CLAUDE.md`): NatSpec ONLY the editable files** — Group A (original work)
  and Group B (forked Nouns, glasses-removed, marked "Yes"). Do **NOT** edit Group C/D files marked
  "No — do not edit" (`*.original`, the ERC-6551 reference under `vault/erc6551/*`, the Nouns libs
  `Inflate`/`SSTORE2`/`NFTDescriptorV2`, `SVGRenderer`/`Inflator`). Their origins, the stripped
  features (esp. Tokenbound's `Overridable` removal + non-upgradeable impl), and their interface
  surface are documented in **curated pages** (`architecture/relationships.md` + a "Forked components"
  section), never by editing the files. `vault/abstract/*` and `vault/lib/*` are "with care" — prefer
  curated docs there too; touch only if genuinely necessary.

## Coverage gate (measurable — replaces "scan for thin pages")

"Every function" needs a precise, reproducible definition (the repo has ~695 function-like
declarations; visual scanning isn't a gate). Define coverage as:

- **In scope (must have full NatSpec):** every contract/library/interface in Groups A + B, and for
  each, **every** `external`/`public` function (`@notice` + `@param` for each arg + `@return` for each
  return), **every** event, and **every** custom error (`@notice`).
- **Internal/private:** in Group A, security-critical internal/private functions require at least
  `@dev` (the escrow/auth/finalize/refund/collect paths especially). Trivial getters/helpers exempt.
- **Out of scope:** Group C/D forked/reference files (documented in curated pages, not edited).

**Reproducible check (build it as part of this work): `script/check-natspec.py`.** Do NOT diff the flat
ABI — an ABI flattens inherited functions and synthesizes public-variable getters, so it would demand
NatSpec on members the contract doesn't declare. Drive the check off the **compiler AST + source
locations** instead (`forge build` with `extra_output = ["ast"]`, or `solc --ast-compact-json`):
- **Attribute by declaration site:** for each in-scope contract, enumerate only the
  `FunctionDefinition` / `EventDefinition` / `ErrorDefinition` / public `VariableDeclaration` nodes
  **declared in that contract's own source** (the node's `src` falls in the in-scope file). This
  automatically **excludes inherited APIs** (incl. inherited Group C/D / OpenZeppelin functions) —
  they're declared elsewhere and documented (or not) at their source.
- **Recognize `@inheritdoc`:** a member whose `documentation` is `@inheritdoc X` counts as documented
  (its tags come from the named base/interface).
- **Public-variable getters:** check the **`VariableDeclaration`'s** own `@notice`/`@dev` (or
  `@inheritdoc`), not the synthesized getter in the ABI.
- **Scope:** Groups A + B only; require `@notice` on every declared external/public function, event,
  and error, `@param`/`@return` on each function arg/return, and at least `@dev` on Group-A
  security-critical internal/private functions. Skip trivial getters/helpers.
- Exit non-zero on gaps so it can gate CI alongside `check-storage-layout.sh` — "documented" becomes a
  build check, not a judgment call.

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

## Source-of-truth inputs

**Authoritative (repo-tracked, portable to all contributors + CI — the docs MUST be derivable from
these alone):**
- The **source code** (NatSpec + comments) — the ground truth.
- `CLAUDE.md` — architecture, layers, invariants, File authority, deploy runbook.
- `AUDIT_REPORT.md`, `REMEDIATION_PLAN.md`, `ARCHITECTURE_REVIEW_A.md` — finding-level detail for the
  auditor-facing sections.
- `docs/storage-layout/*.norm.json` — the storage-gate snapshots.

**Optional background (local to one machine — NOT available to other contributors or CI; never the
sole basis for any documented claim):**
- Project memory `~/.claude/.../memory/project_shwouns.md` and the plan files in `~/.claude/plans/`
  (`what-happens-to-a-lucky-meteor.md`, `hey-claude-we-ve-been-velvet-canyon.md`,
  `audit-findings-critical-deployment-reactive-bachman.md`). Useful design/decision history, but if a
  claim only lives there, move it into a repo-tracked doc before relying on it.

## Suggested order

0. **Done in this branch:** the root `README.md` was refreshed (it's the `forge doc` homepage — must
   not publish stale deploy instructions). Re-verify it still matches before the first generated build.
1. Add `[doc] out = "docs/reference"` to `foundry.toml`; run `forge doc` for the baseline.
2. Build `script/check-natspec.py` (the coverage gate) so "documented" is measurable from the start.
3. NatSpec pass, **Group A → Group B only** (never edit C/D — document those in curated pages).
   Re-run the coverage gate to zero; regenerate `forge doc`.
4. `overview.md` + the system-map diagram (gives everything a spine).
5. The four `flows/` sequence diagrams (highest-value visuals) — incl. the hand-authored **script
   operational reference** in `flows/deployment.md` (forge doc skips `script/`).
6. `architecture/` (relationships, auth-and-trust, storage-layout, "Forked components") + generated SVGs.
7. `concepts/` (community) + `docs/README.md` reading paths, cross-linked to `docs/reference/`.
8. Keep `main` deploy-frozen; docs work merges independently of the Sepolia gate.
