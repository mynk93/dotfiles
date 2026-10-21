## What it does

Three to five sentences, present tense. What goes in, what comes out, who calls it.

## Why this way

- Each bullet names the alternative it beat or the failure it prevents.

## How it works

```svg
<svg viewBox="0 0 760 280" role="img" aria-label="The step turns the input into the output in one pass">
  <defs><marker id="first-chunk-how-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#003D67"/></marker></defs>
  <path class="dg-edge" d="M380 64 V112" marker-end="url(#first-chunk-how-arrow)"/>
  <path class="dg-edge" d="M380 168 V216" marker-end="url(#first-chunk-how-arrow)"/>
  <text class="dg-label" x="388" y="92">sends</text>
  <text class="dg-label" x="388" y="196">returns</text>
  <g><rect class="dg-node" x="296" y="24" width="168" height="40" rx="8"/><text class="dg-name" x="380" y="48">Input</text></g>
  <g><rect class="dg-new" x="296" y="112" width="168" height="56" rx="8"/><text class="dg-name" x="380" y="136">The step</text><text class="dg-sub" x="380" y="152">what this chunk does</text></g>
  <g><rect class="dg-node" x="296" y="216" width="168" height="40" rx="8"/><text class="dg-name" x="380" y="240">Output</text></g>
</svg>
<figcaption>The step turns the input into the output in one pass.</figcaption>
```

## States

None. (Or a state diagram, as an svg fence, when this chunk owns a lifecycle.)

## Traceability

| Requirement or decision | Where | Pinned by |
|---|---|---|
| | | |

## Decisions and assumptions on this chunk

Filled from the ledger by chunk id.

## Review entry points

1. `path/to/file.py`: the question to ask of it.
