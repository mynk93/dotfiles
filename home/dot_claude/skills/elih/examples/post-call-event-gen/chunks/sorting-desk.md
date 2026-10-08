## What it does

Once per claimed record: collect the record and the S3 transcript, fetch the agent's disposition rules, run the detection core, compare, write one fenced result, finish. The core is a pure function over a read-only `CallContext` with no store, queue or bucket access, so FBT and a bench can call it with the same inputs.

NEW detection has four sources and no legacy code (D-33): the harness's own events, an ambient source over call metadata (D-34), DSML's `conved`, and the tenant module from the Field guide. There is no per-call LLM pass.

## Why this way

- Plan before run: filters decide which definitions run and record a reason for every skip, so "skipped" and "ran, nothing found" stay distinct (R2-10 to R2-17).
- Sources are isolated. A harness failure retries the call, because a disposition without tool events is wrong. Any other source failing degrades and is recorded (C-3).
- Rules are written in legacy's names and the tokenizer splits on spaces, so a conved id like `Event: CE/Consumer/Wrong Party` cannot appear in a rule. The disposition is evaluated through the Scorecard's correspondence table until naming is settled (C-4).

## How it works

```mermaid
flowchart TD
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67
    classDef src fill:#F2EDE3,stroke:#003D67,color:#003D67
    DONE{"already done by this detector_version?"} -->|"yes"| FIN["finish, no run"]
    DONE -->|"no"| STAMP["stamp detector_version"] --> COL["Collect: record + S3 transcript"]:::new --> RUL["Rules: config-manager by agent_id, cached 5 min, 24 h fallback"]:::new
    RUL --> PLAN["Plan: filters, first skip wins, reason per event"]:::new
    PLAN --> S1["Harness: in-call emits + tool-call extractors (required)"]:::src
    S1 --> S2["Ambient: call_answered, no_answer, short_call, ... from metadata"]:::src
    S2 --> S3["conved: fabricated proInsight call_struct, LLM groups off"]:::src
    S3 --> S4["Tenant module: may read the hits above; LLM only on a candidate hit"]:::src
    S4 --> MRG["Merge: one event shape, validate proAgent names, drop skipped, order"]:::new
    MRG --> DISP["Disposition: agent rules through correspondence; tags always empty"]:::new
    DISP --> CMP["Scorecard compare (shadow) or live write (live)"]
    CMP --> W["One fenced write under post_call, then finish done"]:::new
```

Plan filters, in order: source availability, known unrunnable conved ids, short call (under 5 s), no consumer speech, modality, empty transcript, tenant filters.

## States

Per-step status under `post_call.steps` (`collect`, `rules`, `detect`, `write`), each with status, duration and error. No state machine beyond the Conveyor's.

## Traceability

| Requirement or decision | Where | Pinned by |
|---|---|---|
| R2-10 to R2-17 plan and filters | `apply/plan.py`, `apply/filters/` | `test_plan.py` |
| R2-18, R2-19 source order and isolation | `apply/run.py`, `apply/sources/` | `test_sources_*.py` |
| D-34 ambient events, parity with legacy extractors | `apply/sources/ambient_source.py` | `test_ambient_source.py` (every disconnect reason) |
| R2-7 conved call_struct fabrication | `apply/adapters/conved_struct.py` | conved lane, Python 3.12 |
| R1E-6 rules by agent_id, latest | `clients/agent_rules.py` | `test_agent_rules.py` |
| FR-15 total failure gives OTHER + inference_failed | `pipeline/core.py` | T1-2 |
| T1-4 idempotent on detector_version | `pipeline/shell.py` | T1-4 |

## Decisions and assumptions on this chunk

Filled from the ledger by chunk id.

## Review entry points

1. `pipeline/core.py` then `pipeline/shell.py`: the step order and where `finish` sits (last).
2. `apply/sources/ambient_source.py`: a table of disconnect reasons to events; check it against your mental model of the call outcomes.
3. `apply/plan.py`: confirm no filter can change the output of a definition that runs.
