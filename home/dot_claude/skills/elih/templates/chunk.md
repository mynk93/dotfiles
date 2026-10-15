## What it does

Three to five sentences, present tense. What goes in, what comes out, who calls it.

## Why this way

- Each bullet names the alternative it beat or the failure it prevents.

## How it works

```mermaid
flowchart TD
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    IN["input"] --> STEP["STEP: what this chunk does"]:::new --> OUT["output"]
```

## States

None. (Or a `stateDiagram-v2` when this chunk owns a lifecycle.)

## Traceability

| Requirement or decision | Where | Pinned by |
|---|---|---|
| | | |

## Decisions and assumptions on this chunk

Filled from the ledger by chunk id.

## Review entry points

1. `path/to/file.py`: the question to ask of it.
