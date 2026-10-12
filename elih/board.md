# Board

## Today's flow and what breaks

```mermaid
flowchart TD
    classDef legacy stroke-dasharray:5 5,stroke:#6B6A66,color:#6B6A66,fill:#fff
    classDef existing fill:#fff,stroke:#003D67,color:#003D67
    REQ["requirements"]:::existing --> G["grilling rounds"]:::existing --> L["ledger rows"]:::existing --> B["board"]:::existing
    G -.-> T["terms and why said aloud, kept only in chat"]:::legacy
```

The grilling elicits vocabulary and reasons, but only decisions have a home in the ledger. Words drift between the ledger and the diagrams, and a reader of a decision row cannot see why it was made.

## Pass 1: Fact-check

```mermaid
flowchart TD
    classDef legacy stroke-dasharray:5 5,stroke:#6B6A66,color:#6B6A66,fill:#fff
    classDef existing fill:#fff,stroke:#003D67,color:#003D67
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    REQ["requirements"]:::existing --> G["grilling rounds"]:::existing --> L["ledger rows"]:::existing --> B["board"]:::existing
    G --> FC["FACT-CHECK: challenge terms, sharpen words, scenarios, cross-reference code"]:::new --> G
```

## Pass 2: Style guide

```mermaid
flowchart TD
    classDef existing fill:#fff,stroke:#003D67,color:#003D67
    classDef earlier fill:#F2EDE3,stroke:#003D67,color:#003D67
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    REQ["requirements"]:::existing --> G["grilling rounds"]:::existing --> L["ledger rows"]:::existing --> B["board"]:::existing
    G --> FC["Fact-check"]:::earlier --> G
    FC --> V["STYLE GUIDE: vocabulary rows"]:::new --> B
    V --> LINT["lint: avoid-word warning on prose"]:::new
```

## Pass 3: Editor's note

```mermaid
flowchart TD
    classDef existing fill:#fff,stroke:#003D67,color:#003D67
    classDef earlier fill:#F2EDE3,stroke:#003D67,color:#003D67
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    REQ["requirements"]:::existing --> G["grilling rounds"]:::existing --> L["ledger rows"]:::existing --> B["board"]:::existing
    G --> FC["Fact-check"]:::earlier --> G
    FC --> V["Style guide"]:::earlier --> B
    L --> GATE{"ADR gate?"}:::new -->|"yes"| WHY["EDITOR'S NOTE: why, collapsed under the row"]:::new --> B
    GATE -->|"no"| B
```

## Context: who talks to whom

```mermaid
flowchart TD
    classDef sys fill:#fff,stroke:#003D67,color:#003D67
    classDef new fill:#FDF1E7,stroke:#EC792B,color:#003D67,stroke-width:2px
    classDef ext fill:#F2EDE3,stroke:#6B6A66,color:#003D67
    H["human"]:::sys --> SK["elih SKILL.md + reference/grilling.md"]:::new
    SK --> LED["elih/ledger.yaml"]:::new --> PY["elih.py lint + render"]:::new --> OUT["board HTML"]:::sys
    UP["mattpocock/skills: grilling, domain-modeling"]:::ext -.->|"vendored, not called"| SK
```
