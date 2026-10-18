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

A diagram earns its place when it shows a mechanism the reader would otherwise assemble from prose: where data flows, which parts talk, what a pass adds, what state a request moves through. If a sentence says it faster, write the sentence.

### What to draw

- **Draw the mechanism, not its name.** A box labelled "queue" says less than a sentence does. Show the path a write takes through the queue, the parts on either side of it, and the edge that disappears without it.
- **Draw the difference.** In a stepper pass, a before and after, or two options side by side, the reader should be able to point at the box or edge that changed. One unconnected box per option is a list, not a comparison.
- **Draw as much as the decision turns on.** A one-hop question needs three boxes. A reroute through a queue needs the writer, the queue, the reader and the ordering edge. A chunk with six or more parts gets a short overview first, then one diagram per sub-flow worth explaining.
- **Draw only what the ledger or the chunk page states.** Leave out any name, number or path you would have to guess. Tie every part to the rest with an edge or a container; a loose box reads as an afterthought.
- **Draw a loop as a return edge, not a ring.** Keep the flow in one direction and route the edge back around the outside.
- **Keep one direction.** Flows run top to bottom and context views left to right. A sequence diagram puts participants across the top, `dg-life` lifelines below them, and messages as horizontal edges 40 apart. A state diagram uses `rx="20"` boxes, a filled start circle, and the event name on each transition.

### Frame

- Each ` ```svg ` fence holds one `<svg viewBox="0 0 760 H" role="img" aria-label="…">` followed by a `<figcaption>`. The renderer wraps the two in a `<figure>`, inlines them unchanged, and never scales the svg past its viewBox width, so 13 px text renders at 13 px. On screens narrower than 640 px the figure scrolls sideways instead of shrinking further.
- The caption states the one claim the picture makes, such as "Writes move to the conveyor; reads stay put", never its topic. The `aria-label` repeats the claim, and lint warns when it is missing. Explanations belong in the caption or the prose, not inside the drawing.
- Use width 760. Go up to 952 only when the drawing will not fit, because 952 is the widest a card draws at 1:1. Grow down instead of wider.
- Set H to the lowest edge or baseline plus 24. Keep every coordinate positive and every label at least 24 clear of the right edge. A label with `text-anchor="end"` grows leftwards, so check where it starts.
- Ids are page-global, because the board and every chunk are tabs on one page. Prefix each id with the diagram's slug, such as `pass2-arrow` or `<chunk-id>-how-arrow`. Lint fails on a repeat.
- Put no `<style>`, `<script>`, `<foreignObject>` or images inside the svg. The page's `dg-*` classes do the styling.
- Hand-written Mermaid fences still render for older boards, and lint warns on them. Mermaid stays loaded for the views LikeC4 generates.

### Text and boxes

- Use 13 px for names and detail lines and 11.5 px for edge labels. Nothing goes below 11. Names take `dg-name`, detail lines `dg-sub`, literal code `dg-code`, and edge labels `dg-label`. Write every label in sentence case.
- SVG never wraps, so break every line yourself and keep a detail line to about five words. Size each box from its longest line using these widths, then add 24 and round up to a multiple of 8.

  | Class | Width per character |
  |---|---|
  | `dg-name` | 7.4 |
  | `dg-sub` | 7.0 |
  | `dg-label` | 6.2 |
  | `dg-code` | 8.0 |

- Count every line before writing its box. A line that doesn't fit gets a wider box or fewer words, never text over the border.
- A box is 40 tall plus 16 per detail line. The name's baseline sits 24 below the box top, and detail lines sit at 40 and 56. Centre the text at x = left + width / 2. Boxes of the same kind share a height.
- Put box corners on a step of 8; edge ports, baselines and labels follow from the box. Leave at least 48 between boxes, and the label's width plus 16 where an edge label sits in the gap. Boxes in a row share a centre y, and boxes in a column share a centre x.
- Write one `<g>` per node, the rect first and then its text, with `rx="8"`. A container `dg-group` leaves 32 at the top for its `dg-lane` name and 16 on the other sides.

### Colour

Colour names a kind of thing, and emphasis comes from contrast. One `dg-new` or `dg-key` among quiet boxes stands out; five do not. Every box of the same kind gets the same class.

| Class | Look | Use for |
|---|---|---|
| `dg-node` | white, navy border | unchanged parts |
| `dg-earlier` | beige | added in an earlier pass |
| `dg-new` | cream, 2 px orange border | new in this pass or this chunk |
| `dg-legacy` | dashed grey | stays until retired |
| `dg-ext` | beige, grey border | external systems and stores |
| `dg-key` | navy, white text | the one hub, at most one per diagram |
| `dg-warn` | dashed dark orange | a known hazard |

Add a `<p class="diagram-legend">` only when an encoding repeats and the caption doesn't explain it. Each entry is a swatch and its meaning, `<span><i class="k-new"></i>New in this pass</span>`. The swatch classes are `k-node`, `k-new`, `k-earlier`, `k-legacy`, `k-ext`, `k-key` and `k-warn` for boxes, and `k-call` and `k-return` for edges.

### Edges

- Draw right angles only, as `M x y H x V y`, through the gaps between boxes. Start and end each edge exactly on a box edge, at the side's midpoint. When two edges share a side, put them a third and two-thirds along it. Stop the line at the boundary instead of running it under a box's fill.
- Before writing an edge, trace it against every box and label already placed. If it would cross one, elbow around through a gap or along a strip at least 24 outside the boxes. Give parallel edges their own tracks.
- Label every edge with what moves along it, such as `writes`, `polls every 30s` or `invalidates`. An unlabelled arrow only says two parts are related somehow. Put the label 8 px beside its line, above a level run or right of an upright one, never on the line. When the gap is narrower than the label, put the label above the row.
- Use `dg-edge` for calls and data, dashed `dg-return` for replies and async work, and orange `dg-hot` for the one path the page is about. Give each svg one marker, and a hot edge its own orange copy, since a marker doesn't take its line's colour:

  ```html
  <marker id="<slug>-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#003D67"/></marker>
  ```

- Draw in this order: `<defs>`, groups, edges, edge labels, nodes.

### Stepper passes

Lay out the final pass first, then cut pass 0 down from it. Each pass copies the previous pass's svg with the same viewBox and every box at the same coordinates. The previous pass's `dg-new` boxes become `dg-earlier`, and this pass's additions are `dg-new`, so the board reads as one system growing. The stepper header's key covers these four classes: new in this pass is `dg-new`, added earlier is `dg-earlier`, unchanged is `dg-node`, and legacy is `dg-legacy`. Stepper diagrams need no legend of their own.

### Check the render

Coordinates are written blind, so look at the result before handing over. Run `elih.py render <dir> --flat -o /tmp/elih-flat.html`, which shows every tab and pass at once, then screenshot it with `npx playwright screenshot --full-page file:///tmp/elih-flat.html /tmp/elih-flat.png` and read the image. The first run needs `npx playwright install chromium`. Fix any line over a border, words cut off at the frame's edge, edge through a box or a label, or labels touching. Re-render until each caption's claim lands at a glance.

## LikeC4 (preferred for context views)

When `npx likec4` runs, the context views come from `elih/model.c4`. The renderer generates them on every `render`:

```bash
npx likec4 gen mermaid -o elih/out/views elih     # default: no browser needed
npx likec4 export png -o elih/out/views elih      # `render --png`; needs `npx playwright install chromium` once
```

A view is embedded wherever the ledger names its id: `feature.context_view` on the board, `chunks[].context_view` at the top of a chunk page. The PNG wins when present, the generated `.mmd` otherwise, and the hand-drawn svg in `board.md` when neither exists. Generated Mermaid uses the `@{ shape: ... }` node syntax, so the page loads Mermaid 11.

Keep the model small: the systems that exist, the new deployable, the stores, the external services. One `view` for the board, one `view <id> of <element>` per chunk. Tag the new deployable `#new` and legacy elements `#legacy`; the styles in the template colour them. The interactive site from `npx likec4 build -o elih/out/site elih` is linked from the board when `out/site/index.html` exists.

Template: `templates/model.c4`.
