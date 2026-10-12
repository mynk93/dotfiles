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
    adr: bool                  # optional. true when hard to reverse AND surprising without context AND a real trade-off
    why: string                # one to three sentences: context, choice, reason. Required when adr is true, omitted otherwise
    adr_file: path             # optional. Only when the repo already has docs/adr/; the row links to the file

sources:                       # what was read at kickoff, mostly context-graph notes. Keyed by note name, no new ids
  - note: string               # graph note name (proAgent-disposition-engine), or a path or URL
    where: string              # optional: repo or system the note lives in
    claim: string              # the one claim taken from it, in one sentence
    used_for: [id]             # pillar or decision ids that rest on it
    result: confirmed | contradicted | unused
    now: string                # required when contradicted: what is true instead

vocabulary:                    # the style guide. Optional; one row per project term, never general programming words
  - term: string               # the one name for the thing
    meaning: string            # one or two sentences, what it IS, no implementation detail
    avoid: [string]            # other words people use for it; lint warns when they appear in board.md or a chunk page
    chunk: chunk id            # optional, the chunk that owns the term

blockers:
  - id: B-n
    chunk: chunk id
    what: string
    owner: you | agent | "agent, then you"

changelog:                     # newest first
  - date: YYYY-MM-DD
    what: string               # one line, in the human's vocabulary
```

## Sources and dissolution

`sources` is the ledger's memory of what it read before asking anything, so that at the end the feature doc can say which shared understanding it confirmed and which it overturned. One row per claim, not per note. A row goes `contradicted` the moment the work proves it wrong, with `now` stating what is true; that is the same moment a pillar resting on it goes `invalidated`.

When every chunk is `merged` or `deployed`, `elih.py dissolve` writes `docs/<slug>.md` beside the `elih/` directory and the `elih/` directory is removed in the same commit. The doc is written in the present tense as a description of what exists: goal, how it works, one section per chunk, the decisions with their Editor's notes, what the work relies on, what is no longer true, the terms, and the notes read. States, attributions, and review order do not survive; they were for the build. The frontmatter carries `graph.read`, `graph.corrects`, `graph.introduces`, and `graph.decisions` so whoever ingests the doc into the context graph can find the beats without the prose addressing the graph.

## Editor's notes and the style guide

A decision row is one sentence. When a decision passes all three of Pocock's ADR tests (hard to reverse, surprising without context, the result of a real trade-off) it is marked `adr: true` and must carry a `why`. The board and chunk pages show `why` collapsed under the row as an "Editor's note", so the one-line summary is unchanged. Lint cannot judge the gate; it only enforces that `adr: true` has a `why`. No file is created for an ADR unless the repo already keeps `docs/adr/`, in which case the agent writes the one-paragraph ADR there and sets `adr_file`.

`vocabulary` is the project's style guide: one name per concept, the words to avoid, and a meaning free of implementation detail. It appears on the board as a collapsed "Words we use" panel below the pillars. Lint warns whenever an avoided word appears in `board.md` or a chunk page, so the guide stays opinionated.

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
