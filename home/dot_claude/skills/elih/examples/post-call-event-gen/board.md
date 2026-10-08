# Board

## Today's flow and what breaks

```mermaid
flowchart TD
    classDef legacy stroke-dasharray:5 5,stroke:#6B6A66,color:#6B6A66,fill:#fff
    classDef existing fill:#fff,stroke:#003D67,color:#003D67
    EC["end_call (room still open)"]:::existing --> LEG["Legacy detection: 2 s LLM budget, no retry"]:::legacy
    LEG --> DBS["db-store"]:::existing --> DB[("Mongo call record")]:::existing
    DB --> OUT["get-call, TCN, EOD, Manthan, CRM, proInsight CSV"]:::existing
    LVW["lv-webhook FAQ tagger (minutes later)"]:::legacy -->|"overwrites events"| DB
```

A miss is permanent and invisible. Two writers race on the same field. Nothing measures quality.

## Pass 1: Stamp and Conveyor

```mermaid
flowchart TD
    classDef legacy stroke-dasharray:5 5,stroke:#6B6A66,color:#6B6A66,fill:#fff
    classDef existing fill:#fff,stroke:#003D67,color:#003D67
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    EC["end_call"]:::existing --> LEG["Legacy detection (unchanged, customer-facing)"]:::legacy
    LEG --> ST["STAMP: post_call pending + in-call emits + AMD detections (served tenants only)"]:::new
    ST --> DBS["One db-store"]:::existing --> DB[("Mongo: legacy fields + post_call")]:::existing
    DBS -->|"only after 2xx"| Q[["CONVEYOR: Redis pointer stream"]]:::new
    Q --> CL["Claim: lease + fence token"]:::new
    REAP["Reaper (expired leases)"]:::new -.-> Q
    SW["Orphan sweep (bounded)"]:::new -.-> Q
    CL <--> DB
    DB -->|"legacy fields only"| OUT["Customer surfaces"]:::existing
```

## Pass 2: Sorting desk and Field guide

```mermaid
flowchart TD
    classDef legacy stroke-dasharray:5 5,stroke:#6B6A66,color:#6B6A66,fill:#fff
    classDef existing fill:#fff,stroke:#003D67,color:#003D67
    classDef earlier fill:#F2EDE3,stroke:#003D67,color:#003D67
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    EC["end_call"]:::existing --> LEG["Legacy detection"]:::legacy --> ST["Stamp"]:::earlier --> DBS["db-store"]:::existing --> DB[("Mongo")]:::existing
    DBS --> Q[["Conveyor"]]:::earlier --> CL["Claim"]:::earlier
    subgraph SD["SORTING DESK (one claimed record)"]
        COL["Collect: record + S3 transcript"]:::new --> RUL["Rules: agent config by agent_id"]:::new --> PLAN["Plan: which definitions run, reason per skip"]:::new
        PLAN --> SRC["Sources in order: harness, ambient, conved, tenant module"]:::new --> MRG["Merge + disposition through correspondence"]:::new
    end
    FG[("FIELD GUIDE: tenant modules @ pinned Git commit")]:::new -.->|"loaded at startup"| SRC
    CL --> COL
    MRG --> SAVE["One fenced write under post_call, then finish"]:::new --> DB
    DB -->|"legacy fields only"| OUT["Customer surfaces"]:::existing
```

## Pass 3: Scorecard

```mermaid
flowchart TD
    classDef legacy stroke-dasharray:5 5,stroke:#6B6A66,color:#6B6A66,fill:#fff
    classDef existing fill:#fff,stroke:#003D67,color:#003D67
    classDef earlier fill:#F2EDE3,stroke:#003D67,color:#003D67
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    EC["end_call"]:::existing --> LEG["Legacy detection"]:::legacy --> ST["Stamp"]:::earlier --> DBS["db-store"]:::existing --> DB[("Mongo")]:::existing
    DBS --> Q[["Conveyor"]]:::earlier --> CL["Claim"]:::earlier --> SD["Sorting desk"]:::earlier
    FG[("Field guide")]:::earlier -.-> SD
    SD --> CMP["SCORECARD: compare NEW vs legacy per call, in legacy's vocabulary"]:::new
    CMP --> SAVE["Fenced write: result + comparison"]:::earlier --> DB
    DB -->|"post_call"| REP["/admin/shadow-report per tenant"]:::new
    DB -->|"legacy fields only"| OUT["Customer surfaces"]:::existing
```

## Pass 4: The Switch

```mermaid
flowchart TD
    classDef legacy stroke-dasharray:5 5,stroke:#6B6A66,color:#6B6A66,fill:#fff
    classDef existing fill:#fff,stroke:#003D67,color:#003D67
    classDef earlier fill:#F2EDE3,stroke:#003D67,color:#003D67
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    EC["end_call"]:::existing --> SWX{"THE SWITCH: tenant in POST_CALL_LIVE_TENANTS?"}:::new
    SWX -->|"no (shadow)"| LEG["Legacy detection"]:::legacy --> ST["Stamp"]:::earlier
    SWX -->|"yes (live)"| STL["Stamp live=true, null the legacy fields"]:::new
    ST --> DBS["db-store"]:::existing
    STL --> DBS
    DBS --> DB[("Mongo")]:::existing
    DBS --> Q[["Conveyor"]]:::earlier --> SD["Sorting desk"]:::earlier
    SD -->|"shadow"| CMP["Scorecard"]:::earlier --> SAVE["Fenced write"]:::earlier --> DB
    SD -->|"live"| LW["Write events, call_disposition_data, tags in today's shapes"]:::new --> DB
    DB --> OUT["Customer surfaces"]:::existing
```

Rollback is removing the tenant from the list. Calls that end afterwards run legacy again; calls already stamped live keep the worker's result.

## Context: who talks to whom

```mermaid
flowchart TD
    classDef sys fill:#fff,stroke:#003D67,color:#003D67
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    classDef ext fill:#F2EDE3,stroke:#6B6A66,color:#003D67
    AO["agent-orchestrator (end_call)"]:::sys -->|"db-store HTTP"| API["proagent-apis (#801: dotted writes)"]:::sys
    AO -->|"XADD pointer"| R[("Redis")]:::sys
    AO -->|"transcript upload"| S3[("S3 redacted bucket")]:::sys
    API --> M[("Mongo, one database per tenant")]:::sys
    W["post-call worker (new deployable)"]:::new -->|"XREADGROUP"| R
    W <-->|"claim, fenced writes"| M
    W -->|"read transcript"| S3
    W -->|"disposition rules by agent_id"| CM["config-manager"]:::ext
    W -->|"import, pinned"| CV["conved (DSML library)"]:::ext
    W -->|"tarball @ sha, read-only token"| GH["GitHub: tenant modules"]:::ext
    W -->|"CAM classifiers only"| TFY["TrueFoundry LLM gateway"]:::ext
    M --> DS["Downstream: get-call, TCN, EOD, Manthan, CRM, proInsight CSV"]:::sys
```
