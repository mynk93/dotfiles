# The standard view set

Same views, same order, same colours on every page. The set is lifted from ISO/IEC/IEEE 42010 (named viewpoints with rationale), IEEE 1016 (context, composition, interaction, state dynamics, deployment) and ISO/IEC/IEEE 29148 (traceability from requirement to design to test), with C4 as the zoom ladder. The human builds muscle memory only if nothing moves between pages.

## Board (L0)

1. **Hero**: goal, the one artifact to review, branch and head, metaphor pill.
2. **Blocked on you** beside **Since your last visit**.
3. **Chunk grid** in review order, each card with a stage bar and risk colour.
4. **Pillars** table.
5. **Stepper**: pass 0 is today's flow and what breaks; one pass per chunk after that. Every pass keeps every box from the pass before. Colour key: new in this pass (orange outline, cream fill), added earlier (beige), unchanged (white), legacy (dashed grey). Flow top to bottom.
6. **Context view**: who talks to whom. C4 level 1 to 2. From LikeC4 when available.
7. **How to review**: the chunk table by `review_order` with `risk_why` and `size`.
8. **Done when**.

## Chunk page (L1), six sections in this order

1. **What it does.** Three to five sentences. Present tense.
2. **Why this way.** Bullets. Each names the alternative it beat or the failure it prevents.
3. **How it works.** One diagram: a sequence diagram when the chunk is an interaction between parties, a flowchart when it is a pipeline. Top to bottom. If LikeC4 is in use, a `dynamic view` scoped to the chunk's elements is exported here as well.
4. **States.** A state diagram when the chunk owns a lifecycle, otherwise the line "None" and what owns the state instead.
5. **Traceability.** Table: requirement or decision id, where (file or symbol), pinned by (test id or file). Every row in the chunk's ledger entries appears here or is explicitly untested.
6. **Decisions and assumptions on this chunk.** Generated from the ledger; the page carries the placeholder line `Filled from the ledger by chunk id.` and the renderer replaces it.
7. **Review entry points.** Numbered, at most three, each one file or function and the question to ask of it.

Two further views from the standard belong on a deployment-type chunk when one exists: a **component view** (C4 level 3) and a **deployment view**.

## Diagram conventions

Every diagram is hand-placed inline SVG in an ` ```svg ` fence. The renderer inlines the fence as-is inside a `.diagram` box and caps it at its viewBox width, so it draws at 1:1. The method (plan the inventory, 8 px grid, box width from text, orthogonal edges on box edges, numbered badges with a key table, draw order) is pro-html's: read `~/.claude/plugins/marketplaces/proPlugins/skills/pro-html/references/svg-diagrams.md` before drawing. Elih keeps its own palette, so these are the differences:

- **Canvas.** viewBox width 800. Go up to 952 only when it won't fit; that is the widest that still draws at 1:1 in a card. Grow down rather than wider.
- **Node kinds.** `dg-node` unchanged (white, navy border), `dg-earlier` added in an earlier pass (beige), `dg-new` new in this pass or this chunk (cream, 2 px orange border), `dg-legacy` stays until retired (dashed grey, grey text), `dg-ext` external system or store (beige, grey border), `dg-key` the one hub (navy, white text), `dg-warn` a known hazard (dashed dark orange). Every kind used goes in a `<p class="diagram-legend">` with `<i class="k-<kind>">` swatches, inside the fence after the `</svg>`.
- **Edges.** `dg-edge` solid, `dg-return` dashed, `dg-hot` the one path the page is about. Markers fill `#003D67` (`#EC792B` for a hot edge's marker).
- **Ids are page-global.** The board and every chunk are tabs on one page. Prefix every id with the diagram's slug (`pass2-arrow`, `<chunk-id>-how-arrow`); lint fails on a repeat.
- **Key table.** Numbered badges are explained in a markdown table right after the fence: `#` · `From → to` · `What happens`, with `<span class="num">1</span>` in the first cell.
- **Stepper.** Lay out the final pass first, then cut pass 0 down from it. Every pass copies the previous pass's svg with the same viewBox and every box at the same coordinates. The previous pass's `dg-new` boxes become `dg-earlier`; this pass's additions are `dg-new`. The board then reads as one system growing.
- **Flow top to bottom.** Sequence diagrams put participants across the top; state diagrams use `rx="22"` boxes and a filled start circle.
- Chunk names appear in upper case the first time a diagram introduces the chunk ("CONVEYOR" with "Redis pointer stream" as its detail line) and plain afterwards.

Mermaid stays loaded for LikeC4-generated views and old boards. Lint warns on a hand-written Mermaid fence.

**Check the render.** Hand-placed coordinates are never right the first time. Run `elih.py render <dir> --flat -o /tmp/elih-flat.html` (every tab and pass shown at once), then pro-html's `scripts/snap /tmp/elih-flat.html` from the same plugin directory. Fix every SVG layout issue it reports, ignore its brand section (elih keeps the older fonts and colours on purpose), and Read the `svg-N.png` files before handing over.

## LikeC4 (preferred for context views)

When `npx likec4` runs, the context views come from `elih/model.c4`. The renderer generates them on every `render`:

```bash
npx likec4 gen mermaid -o elih/out/views elih     # default: no browser needed
npx likec4 export png -o elih/out/views elih      # `render --png`; needs `npx playwright install chromium` once
```

A view is embedded wherever the ledger names its id: `feature.context_view` on the board, `chunks[].context_view` at the top of a chunk page. The PNG wins when present, the generated `.mmd` otherwise, and the hand-drawn svg in `board.md` when neither exists. Generated Mermaid uses the `@{ shape: ... }` node syntax, so the page loads Mermaid 11.

Keep the model small: the systems that exist, the new deployable, the stores, the external services. One `view` for the board, one `view <id> of <element>` per chunk. Tag the new deployable `#new` and legacy elements `#legacy`; the styles in the template colour them. The interactive site from `npx likec4 build -o elih/out/site elih` is linked from the board when `out/site/index.html` exists.

Template: `templates/model.c4`.
