---
name: elih
description: "Explain like I'm human. Keeps one living orientation surface for a multi-session feature: a board (what's blocked on the human, what moved, chunk status), one page per chunk with a fixed view set, and a decision ledger with states. Use at the start of a feature ('set up elih', 'kick off'), at the end of every run that changed code on a feature whose repo has an elih/ledger.yaml, and whenever the human says 'where are we', 'orient me', 'I'm lost', 'brief the team', or '/elih'. Also fires on 'elih ack'."
---

# elih

One surface the human returns to, updated in place every run, generated from a ledger the agent must keep honest. The human reads top down and stops when satisfied; the agent reads all of it at session start instead of re-reading the thread.

It exists because long agent-driven features drown the human in entities: invented ID namespaces, stacked PRs, docs that go stale between reads, and "decisions for you" buried at section 5 of a 6k-character handoff that quietly become the plan when nobody answers. The cure is a budget on entities, one board, and a ledger where every assumption has a state.

## Principles

1. **Entity budget.** At most seven chunks per feature, named from one real-world metaphor chosen with the human at kickoff. No new chunk, id namespace, document, branch or worktree without a ledger row first. Abstract prefixes (S3, R1E-O11, Part 2) are the enemy; a chunk is "the Conveyor", never "S2".
2. **One surface, regenerated.** The source is `elih/` in the repo on the feature branch. The HTML is a derived view, rebuilt every run, never edited by hand and never the source of truth.
3. **Pillars stop the world.** A pillar is an assumption that invalidates the plan if false. The agent may not build past one run on a pillar in state `needs-you`. Every other choice is a decision with a state; the agent proceeds and logs it.
4. **Recommended never hardens.** A decision in state `recommended` or `assumed` stays visible on the board until the human flips it. Silence is not approval. Re-ask in the same place, never in a new message.
5. **Compression gradient.** L0 board fits one screen. L1 chunk pages are one page each with the same six sections in the same order, so the layout becomes muscle memory. L2 is everything else, linked, unbounded.
6. **Standard views.** Every chunk page carries the fixed view set from [`reference/views.md`](reference/views.md): where it sits, how it works, states, traceability, decisions, review entry points. Context views come from a LikeC4 model when the toolchain is available, Mermaid otherwise. Same look everywhere.
7. **Subagents never write the ledger.** The main agent folds each handback into the chunk page and ledger, so a subagent's choices are visible to the human.
8. **It dissolves.** `elih/` exists only while the feature is being built. When every chunk is merged or deployed it becomes one feature doc in the source repo, in the authoritative voice of what exists, and the directory is removed. The doc keeps the decisions and the reasons that a thread or a PR would lose, and names what it read and what it overturned, so the human can carry it into the context graph.

## Layout

```
elih/
  ledger.yaml        feature, metaphor, chunks, pillars, decisions, blockers, changelog, last_ack
  board.md           progressive-reveal passes (one ## per pass) + the context section
  chunks/<id>.md     one page per chunk, six sections in fixed order
  model.c4           optional LikeC4 model; the context views are exported from it
  out/               generated HTML and PNGs; gitignored
docs/<slug>.md       what elih/ becomes on dissolve; elih/ is removed in the same commit
```

Schema and states: [`reference/ledger-schema.md`](reference/ledger-schema.md). Kickoff interview: [`reference/grilling.md`](reference/grilling.md). Vocabulary and Editor's notes: the "Editor's notes and the style guide" section of the schema. Templates in `templates/`.

The script is `scripts/elih.py` (Python 3.9+, PyYAML). Subcommands: `init`, `lint`, `render`, `ack`, `status`, `dissolve`.

## Procedure

### A. Kickoff (once per feature)

Fires on "set up elih", "kick off", or when a feature has requirements but no `elih/` directory.

1. Read the requirements and the repo. Look up every fact you can before asking anything. If a context-graph clone is reachable (ask once, or use `$LINT_LOCAL_REPOS_ROOT`), read its router, the relevant hub, and the glossary first. Record each claim taken from a note as a `sources` row with the pillar or decision ids that will rest on it. Treat a note as a pointer to verify, not as evidence; `verified` still needs the code or the system.
2. **Grill the human.** Run a grilling session per [`reference/grilling.md`](reference/grilling.md): invoke the `grilling` skill if it is available, else follow the vendored protocol. Root the design tree in the seed questions on that page: goal and first release, the three metaphors with chunk names (at most seven, concrete nouns from the metaphor's world), pillars, what exists and must not change, who else reads the board, the autonomy setting, the review artifact and order. Ask each frontier in one round with a recommended answer per question. Stop when the frontier is empty or the human says "enough".
3. **Land every answer in the ledger.** Accepted recommendations become `approved` decisions with the question number in `by`. "You decide" becomes `assumed`. "I don't know" becomes `needs-you`. Questions left unasked when the human stopped early become `needs-you` rows, never dropped. Terms sharpened during the interview become `vocabulary` rows. A decision that is hard to reverse, surprising without context, and a real trade-off gets `adr: true` and a one-to-three-sentence `why`. The chosen metaphor is frozen; a later rename needs a changelog row.
4. Run `elih.py init <dir> --feature <slug>` to scaffold, then fill `ledger.yaml`, `board.md` with pass 0 (today) and one pass per chunk, and one `chunks/<id>.md` per chunk. Empty sections are allowed at kickoff but must say "not built yet", never be deleted.
5. If `npx likec4` is available, write `model.c4` with the systems, the new deployable, and the stores. One `view` for the board context and one scoped `view` per chunk.
6. `elih.py lint` must pass. `elih.py render`. Show the human the board.

Done when: the human confirmed shared understanding (or stopped the grilling and the leftover frontier is on the board), the metaphor is frozen, every pillar has a state, lint passes, and the board renders.

### B. Per-run update (end of every run that changed code or plan)

1. For each chunk touched: update `stage`, `stage_note`, `paths`, `size`. A chunk's stage drops back to `tested` when its files change after the review that earned `reviewed`.
2. Every choice made this run becomes a ledger row: `assumed` if the agent chose and moved on, `recommended` if it wants the human's answer, `needs-you` if it cannot proceed. Cite the chunk. One sentence, plus a collapsed `why` only when the ADR gate holds. New terms go in `vocabulary`; lint warns when prose uses a word the style guide avoids.
3. Every subagent handback: fold its decisions into the ledger under the main agent's name, and its findings into the chunk page.
4. Append changelog rows for what moved. Dated, one line each, in the human's words not the agent's.
5. Re-check every pillar against what was learned. A pillar found false becomes `invalidated` with the evidence, and the board shows it first. If the pillar rested on a `sources` row, that row becomes `contradicted` with `now` filled in; say so in the handoff, since the graph is now wrong and only the human can fix it.
6. `elih.py lint`, then `elih.py render`. End the run with the board's "Blocked on you" list, verbatim, as the last section of the handoff. Nothing else from the board is repeated in chat.

Done when: lint passes, the HTML is regenerated, and the handoff's last section is the blocked-on-you list.

### C. Ack (the human says "elih ack" or "/elih ack")

`elih.py ack` writes today's date to `feature.last_ack` and re-renders. The "since your last visit" panel then shows only changelog rows after that date.

### D. Orient (the human says "where are we", "I'm lost", "orient me")

Do not write a recap in chat. `elih.py status` prints the board's L0 as text (blocked on you, changelog since ack, chunk stages, pillars). Paste that, then `elih.py render` and give the path. If the board is stale relative to the code (lint warns on `status_date` older than the last commit), run procedure B first.

### E. Brief the team

The same HTML with L1 and L2 collapsed is the briefing. Nothing separate is produced. The human presents the board and the stepper; questions go to the chunk pages.

### F. Dissolve (every chunk merged or deployed)

1. Resolve what can be resolved: every `recommended` and `assumed` row is either flipped to `approved` or `rejected` by the human, or stays and is listed as still open in the doc. Every `sources` row has a result.
2. `elih.py dissolve` writes `docs/<slug>.md` beside `elih/` (pass `-o` to put it elsewhere). It refuses while a chunk is short of `merged` unless `--partial` is given, and then the doc says which parts are unfinished.
3. Read the doc as a stranger. It must describe what exists, in the present tense, with no "we decided" or "the agent assumed". Fix prose that only made sense during the build. Keep every Editor's note.
4. When chunks span more than one repo, split the chunk sections into a doc per repo, each with the full Decisions and Terms sections, and keep the frontmatter on each.
5. Remove `elih/` with `git rm -r` in the same commit as the doc. Link the doc from the repo's docs index if one exists.
6. Tell the human the doc path and that it is ready to ingest into the context graph. Elih does not run the ingest.

Done when: the doc is committed, `elih/` is gone, and the handoff names the doc path.

## The autonomy dial

Which classes gate is per feature, recorded as `feature.autonomy` in the ledger:

| Setting | Pillars | Decisions |
|---|---|---|
| `tight` | gate every run | `recommended` blocks the next run until answered |
| `normal` (default) | gate every run | logged, never block |
| `loose` | gate only when `invalidated` | logged |

Change it only when the human says so, with a changelog row.

## What elih is not

It is not the PR description, the design doc, or the changelog. Those are L2. It links to them. It is not a standing interview either: grilling runs once at kickoff, and later questions wait on the board as rows. It is not permanent: the feature doc is, and it is written for a reader who never saw the board. When content would fit in a chunk page or in a design doc, the design doc wins and the chunk page links to the section.
