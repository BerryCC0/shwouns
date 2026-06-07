# Generated diagrams

Auto-generated structural diagrams for Shwouns, committed as SVGs so they render on GitHub without a
build step. These **complement** the hand-authored Mermaid diagrams (which carry the protocol
*semantics* the auto-tools can't infer): the system map in [overview.md](../../overview.md#the-layers)
and the sequence/state diagrams under [flows/](../../flows/governance-lifecycle.md).

## Files

| File | What | Tool |
|---|---|---|
| `class-diagram.svg` | Contract class diagram — inheritance + associations across `src/` | `sol2uml class` |
| `inheritance.svg` | Contract inheritance graph | `surya inheritance` + graphviz `dot` |

These complement the hand-authored Mermaid **[system map](../../overview.md#the-layers)** (the
highest-value relationship view, which carries the call/value/auth edges the auto-tools can't infer).

Not committed (tooling limitations in the generating environment — regenerable where the tools
cooperate):
- **Call graph** (`surya graph`) — the `graph` subcommand hit a `yargs` incompatibility here while
  `inheritance` worked; the `sol2uml class` diagram and the Mermaid system map cover relationships.
- **Storage slot maps** (`sol2uml storage`) — `sol2uml` doesn't resolve foundry remappings
  (`@openzeppelin/… → lib/…`), so it can't compile the proxies here. The **authoritative** storage
  artifacts are the JSON snapshots in [`../../storage-layout/`](../../storage-layout/) (from `forge
  inspect`), narrated in [storage-layout.md](../storage-layout.md); the SVGs are only a visual
  companion. To render them, flatten first (`forge flatten`) or run `sol2uml` with the imports
  resolved.

If an SVG is absent, the tooling wasn't available when the docs were last built — every diagram is
regenerable from source with the commands below.

## Prerequisites

```bash
npm i -g surya sol2uml      # graph + UML generators
brew install graphviz       # provides `dot`, which surya pipes into (macOS)
```

## Regenerate

Run from the repo root:

```bash
# Class diagram (inheritance + associations) — the relationship view that renders cleanly here.
sol2uml class ./src -o docs/architecture/diagrams/class-diagram.svg

# Inheritance graph.
surya inheritance $(find src -name '*.sol') | dot -Tsvg > docs/architecture/diagrams/inheritance.svg

# (Optional, env-dependent) Cross-contract call graph — surya's `graph` command may fail on a
# yargs incompat; if it works:
surya graph $(find src -name '*.sol') | dot -Tsvg > docs/architecture/diagrams/call-graph.svg

# (Optional, env-dependent) Storage slot maps — sol2uml needs imports resolved (remappings); flatten
# first if it can't find @openzeppelin/* sources:
sol2uml storage ./src -c ShwounsDAOLogic      -o docs/architecture/diagrams/storage-ShwounsDAOLogic.svg
sol2uml storage ./src -c ShwounsAuctionHouse  -o docs/architecture/diagrams/storage-ShwounsAuctionHouse.svg
```

> `surya mdreport $(find src -name '*.sol')` also produces a useful per-contract function table if
> you want a textual companion.
