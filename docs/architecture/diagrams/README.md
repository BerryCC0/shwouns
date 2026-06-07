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
| `call-graph.svg` | Contract-level calls reachable from the governance facade | `surya graph --simple` |
| `storage-ShwounsDAOLogic.svg` | DAO proxy implementation storage | `sol2uml storage` |
| `storage-ShwounsAuctionHouse.svg` | Auction proxy implementation storage | `sol2uml storage` |

These complement the hand-authored Mermaid **[system map](../../overview.md#the-layers)** (the
highest-value relationship view, which carries the call/value/auth edges the auto-tools can't infer).

Surya and sol2uml do not resolve Foundry remappings themselves. The regeneration script first uses
`forge flatten` to supply each tool with the complete inherited source. The storage SVGs are visual
companions only: the **authoritative** storage artifacts are the JSON snapshots in
[`../../storage-layout/`](../../storage-layout/) (from `forge inspect`), narrated in
[storage-layout.md](../storage-layout.md).

If an SVG is absent, the tooling wasn't available when the docs were last built — every diagram is
regenerable from source with the commands below.

## Prerequisites

```bash
npm i -g surya sol2uml      # graph + UML generators
brew install graphviz       # provides `dot`, which surya pipes into (macOS)
```

## Regenerate

Run the reproducible generator from the repo root:

```bash
./script/generate-diagrams.sh
```

The class and inheritance diagrams can still be regenerated independently:

```bash
sol2uml class ./src -o docs/architecture/diagrams/class-diagram.svg
surya inheritance $(find src -name '*.sol') |
  dot -Tsvg -o docs/architecture/diagrams/inheritance.svg
```

> The call graph deliberately uses Surya's `--simple` contract-level view. Its function-level graph
> for the flattened governance surface is several megabytes and too wide to be useful.
