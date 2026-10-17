## What it does

Three to five sentences, present tense. What goes in, what comes out, who calls it.

## Why this way

- Each bullet names the alternative it beat or the failure it prevents.

## How it works

```svg
<svg viewBox="0 0 800 328" role="img" aria-label="Input goes through this chunk's step and comes out as output">
  <defs><marker id="first-chunk-how-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L10 5L0 10z" fill="#003D67"/></marker></defs>
  <path class="dg-edge" d="M400 68 V132" marker-end="url(#first-chunk-how-arrow)"/>
  <path class="dg-edge" d="M400 196 V260" marker-end="url(#first-chunk-how-arrow)"/>
  <g><rect class="dg-node" x="316" y="24" width="168" height="44" rx="10"/><text class="dg-name" x="400" y="51">Input</text></g>
  <g><rect class="dg-new" x="316" y="132" width="168" height="64" rx="10"/><text class="dg-name" x="400" y="159">STEP</text><text class="dg-sub" x="400" y="178">what this chunk does</text></g>
  <g><rect class="dg-node" x="316" y="260" width="168" height="44" rx="10"/><text class="dg-name" x="400" y="287">Output</text></g>
</svg>
<p class="diagram-legend"><span><i class="k-new"></i>This chunk</span><span><i class="k-node"></i>Existing</span></p>
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
