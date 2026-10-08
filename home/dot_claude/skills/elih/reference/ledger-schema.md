# ledger.yaml schema

The ledger is the only source the board is generated from. Quote every value that contains ` #` (PR and issue references start YAML comments otherwise). `elih.py lint` enforces everything below.

```yaml
feature:
  name: string                 # human title
  slug: string                 # kebab-case, used for file names
  goal: string                 # two or three sentences
  done_when: [string]          # the finish line, checkable
  artifact_to_review: url      # the ONE thing to review right now (PR, branch, doc)
  branch: string
  head: string                 # short sha the board was last generated at
  epic: url                    # optional
  status_date: YYYY-MM-DD      # set by render
  last_ack: YYYY-MM-DD | null  # set by ack
  autonomy: tight | normal | loose

metaphor:
  chosen: string
  rationale: string            # one paragraph mapping the metaphor to the flow
  alternatives_considered: [string]

chunks:                        # 1 to 7 entries
  - id: kebab-case             # file name under chunks/
    name: string               # the metaphor noun, capitalised
    one_liner: string
    stage: built | tested | reviewed | merged | deployed
    stage_note: string         # what earned the stage, or what is missing
    risk: high | medium | low
    risk_why: string           # one sentence; shown in the review-order table
    paths: [string]            # directories or files, repo-relative
    size: string               # "12 files, +452 / -26"
    review_order: int          # unique, 1..n, riskiest first

pillars:                       # 3 to 6 entries
  - id: P1, P2, ...
    statement: string          # an assumption, phrased so it can be false
    state: verified | assumed | needs-you | invalidated
    evidence: string           # what makes it verified, or what would
    chunk: chunk id

decisions:
  - id: string                 # D-n for product decisions, C-n for choices; never a new prefix
    chunk: chunk id
    summary: string            # one sentence, the choice and the alternative it beat
    state: assumed | recommended | approved | rejected | superseded | needs-you
    by: string                 # "you, 2026-10-06 (quote)" or "agent, 2026-10-06"

blockers:
  - id: B-n
    chunk: chunk id
    what: string
    owner: you | agent | "agent, then you"

changelog:                     # newest first
  - date: YYYY-MM-DD
    what: string               # one line, in the human's vocabulary
```

## States

| State | Meaning | Board placement |
|---|---|---|
| `needs-you` | the agent cannot proceed past this run without an answer | Blocked on you, first |
| `invalidated` | a pillar found false; the plan is wrong until it is replaced | Blocked on you, first, warn style |
| `recommended` | the agent proposed; the human has not answered | Blocked on you |
| `assumed` | the agent chose and moved on; reversible | chunk page only |
| `approved` | the human said yes; cite the words and date in `by` | ledger tab |
| `rejected` | the human said no; keep the row so the id never dead-ends | ledger tab |
| `superseded` | replaced by a later row; name it in `by` | ledger tab |
| `verified` | pillar confirmed by test or inspection; cite it in `evidence` | pillars table |

## Stage rules

- `built`: code exists on the branch.
- `tested`: the chunk's tests pass on the current head, with the lane named in `stage_note`.
- `reviewed`: a review skill or a human reviewed the chunk's files at a head that still contains them unchanged. Any later change to `paths` drops the chunk to `tested`.
- `merged`: on the default branch.
- `deployed`: running in the named environment.

A chunk's stage never exceeds the stage of a chunk it depends on for its tests. State the dependency in `stage_note` when it bites.
