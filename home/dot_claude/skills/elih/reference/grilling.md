# Grilling at kickoff

Kickoff opens with a grilling session before anything is written to the ledger. The point is to pull the shape of the feature out of the human's head while it is still cheap to change, and to make sure nothing is silently assumed. The interview protocol is Matt Pocock's `grilling` skill (MIT, [mattpocock/skills](https://github.com/mattpocock/skills), `skills/productivity/grilling`). `grill-me` and `grill-with-docs` are user-invoked wrappers over it; elih calls the primitive.

## Which copy runs

1. If a skill named `grilling` is listed as available, invoke it with the Skill tool and follow it. It is the upstream copy and may be newer than this page.
2. Otherwise follow the protocol below. It is a verbatim restatement of the upstream protocol as of 2026-10, plus the elih-specific seed tree and the rule for landing answers in the ledger.

## The protocol

Interview the human until you reach a shared understanding. Map the feature as a **design tree**: every decision branches into the decisions that hang off it.

Work the tree in **rounds**. The **frontier** is every decision whose prerequisites are already settled, meaning the questions you can ask now without guessing at answers you have not heard yet. Ask the whole frontier in one round. Number each question and give your recommended answer. Then wait for the human's answers before the next round.

Format a round like so:

```
❓ **Q1** - **<question title>**: <question body, may be several paragraphs, may list choices>

➡️ <your recommended answer>

---

❓ **Q2** - **<question title>**: <question body>

➡️ <your recommended answer>
```

Word each question so "yes" accepts your recommended answer.

Each round the human answers reshapes the tree. Settled decisions push the frontier outward and unblock questions that depended on them. Recompute the frontier and ask the next round. A question whose answer depends on another question still open in this round belongs to a later round, not this one.

Finding **facts** is your job, never the human's. When a frontier question needs a fact from the environment (the repo, a schema, a service's behaviour), dispatch a sub-agent or look it up yourself. Do not block on it: a running lookup is an unsettled prerequisite, so only the questions downstream of it wait. Ask the rest of the frontier now. The **decisions** are the human's: put each to them and wait.

The session is done when the frontier is empty: every branch visited, nothing left silently assumed. Do not scaffold until the human confirms you have reached a shared understanding.

## The elih seed tree

Root the tree in the questions the ledger needs answered. Everything else branches from these.

| Root question | Feeds |
|---|---|
| What moves from where to where, and what is the smallest first release? | `feature.goal`, `feature.done_when` |
| Which of these three metaphors, with these chunk names? | `metaphor`, `chunks[]` |
| Which assumptions, if false, stop everything? Which can you confirm today? | `pillars[]` |
| What already exists that this must plug into, and what must not change? | `chunks[].paths`, `legacy` nodes on the board |
| Who reads the board besides you, and what do they need from it? | `board.md` context section, which L1 sections are collapsed in a brief |
| How much should the agent decide alone on this feature? | `feature.autonomy` |
| What is the artifact you will review, and in what order? | `feature.artifact_to_review`, `chunks[].review_order` |

The metaphor question is a normal frontier question: propose the three metaphors with chunk names as the choices, recommend one, and let "yes" freeze it. Pillar questions come after the goal is settled, since a pillar is relative to a goal. Chunk-level questions (how a chunk works, what it stores) come after the metaphor is frozen, so they can use the chunk's name.

## Landing answers in the ledger

Nothing said in the interview stays only in chat. After the human confirms shared understanding, and before `elih.py init`:

| What happened in the interview | Ledger row |
|---|---|
| Human accepted a recommended answer | decision, `state: approved`, `by: you, <date> (Q<n>)` |
| Human rejected it and chose otherwise | decision for their choice, `state: approved`, `by: you, <date> (Q<n>: "<their words>")`; the recommendation is not recorded |
| Human said "you decide" or "don't care" | decision, `state: assumed`, `by: agent, <date> (Q<n>)` |
| Human said "I don't know" or "ask <someone>" | pillar if it stops the plan, else decision, `state: needs-you`, with the open question as the summary |
| A fact the agent looked up settled a question | pillar `state: verified` with the evidence, or the fact goes in the chunk page, no decision row |
| Human ended the session before the frontier was empty | every unasked frontier question becomes a `needs-you` row; none are dropped |

Quote the human where their wording carries intent. Keep each summary to one sentence: the choice and the alternative it beat.

Add one changelog row: `grilled: <rounds> rounds, <questions> questions, <needs-you count> left open`.

## Ending early

The human may stop the session at any point with "enough" or "scaffold it". That is a normal exit, not a failure. The frontier at that moment is written down as `needs-you` rows and shows on the board under "Blocked on you", so the questions are re-asked in the same place every run until answered (principle 4). The agent may not build past one run on a pillar left open this way (principle 3).

## What grilling is not

It is not a per-run ritual. It runs once at kickoff. Later questions go on the board as `recommended` or `needs-you` rows and are answered by the human on their own schedule. If the human wants a second grilling mid-feature, they invoke `/grill-me` themselves and the agent lands the answers with the same table above.
