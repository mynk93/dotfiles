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

Two views in the standard that the example does not carry yet, and that belong on the deployment-type chunk: a **component view** (C4 level 3) and a **deployment view**. Add them when the chunk exists.

## Mermaid conventions

```
classDef legacy stroke-dasharray:5 5,stroke:#6B6A66,color:#6B6A66,fill:#fff
classDef existing fill:#fff,stroke:#003D67,color:#003D67
classDef earlier fill:#F2EDE3,stroke:#003D67,color:#003D67
classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
classDef warn fill:#fff,stroke:#D86919,color:#D86919,stroke-dasharray:4 4
```

- `flowchart TD` always. Sequence and state diagrams are vertical by nature.
- Node ids are short upper-case tokens; labels are quoted strings. Keep the same id for the same box across all passes so the stepper reads as one system growing.
- Chunk names appear in upper case inside a label the first time the chunk is introduced ("CONVEYOR: Redis pointer stream") and plain afterwards.
- Edge labels in quotes. No HTML in labels.

## LikeC4 (preferred for context views)

When `npx likec4` runs, the context views come from `elih/model.c4`. The renderer generates them on every `render`:

```bash
npx likec4 gen mermaid -o elih/out/views elih     # default: no browser needed
npx likec4 export png -o elih/out/views elih      # `render --png`; needs `npx playwright install chromium` once
```

A view is embedded wherever the ledger names its id: `feature.context_view` on the board, `chunks[].context_view` at the top of a chunk page. The PNG wins when present, the generated `.mmd` otherwise, and the hand-written Mermaid block in `board.md` when neither exists. Generated Mermaid uses the `@{ shape: ... }` node syntax, so the page loads Mermaid 11.

Keep the model small: the systems that exist, the new deployable, the stores, the external services. One `view` for the board, one `view <id> of <element>` per chunk. Tag the new deployable `#new` and legacy elements `#legacy`; the styles in the template colour them. The interactive site from `npx likec4 build -o elih/out/site elih` is linked from the board when `out/site/index.html` exists.

Template: `templates/model.c4`.
