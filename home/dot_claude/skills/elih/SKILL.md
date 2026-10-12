---
name: elih
description: "Explain like I'm human: a board, chunk pages and a decision ledger kept in elih/ for a multi-session feature. Use at kickoff ('set up elih', 'kick off'), at the end of every run that changed code or plan in a repo with elih/ledger.yaml, when the human says 'where are we', 'brief the team', 'elih ack' or '/elih', and to dissolve elih/ into a feature doc once every chunk is merged ('close out', 'dissolve')."
---

# elih

One board the human returns to, updated in place every run, generated from a ledger the agent keeps honest. The human reads top down and stops when satisfied. The agent reads all of it at session start instead of re-reading the thread.

It exists because long agent-driven features drown the human in entities: invented ID namespaces, stacked PRs, docs that go stale between reads, and "decisions for you" buried at section 5 of a 6k-character handoff that quietly become the plan when nobody answers. The cure is a budget on entities, one board, and a ledger where every assumption has a state.

## Principles

1. **Entity budget.** At most seven chunks per feature, named from one real-world metaphor chosen with the human at kickoff. A new chunk, id namespace, document, branch or worktree gets a ledger row before it exists. A chunk is "the Conveyor"; abstract prefixes (S3, R1E-O11, Part 2) are the enemy.
2. **One board, regenerated.** The source is `elih/` in the repo on the feature branch. The HTML is a derived view, rebuilt every run by the script and read only.
3. **Pillars stop the world.** A pillar is an assumption that invalidates the plan if false. A pillar in state `needs-you` gives the agent one run; after that it waits. Every other choice is a decision with a state; the agent proceeds and logs it.
4. **Recommended never hardens.** A decision in state `recommended` or `assumed` stays on the board until the human flips it. Silence leaves it where it is. The board re-asks in the same place every run.
5. **Compression gradient.** L0 board fits one screen. L1 chunk pages are one page each with the same six sections in the same order, so the layout becomes muscle memory. L2 is everything else, linked, unbounded.
6. **Standard views.** Every chunk page carries the fixed view set from [`reference/views.md`](reference/views.md): where it sits, how it works, states, traceability, decisions, review entry points. Context views come from a LikeC4 model when the toolchain is available, Mermaid otherwise. Same look everywhere.
7. **Subagents never write the ledger.** The main agent folds each handback into the chunk page and ledger, so a subagent's choices are visible to the human.
8. **It dissolves.** `elih/` lives only while the feature is being built. When every chunk is merged or deployed it becomes one feature doc in the source repo, written as a description of what exists, and the directory goes. The doc keeps the decisions and reasons a thread or a PR would lose, and names what it read and what it overturned, so the human can carry it into the context graph.

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

The ledger schema, states, stage rules, Editor's notes and the style guide are in [`reference/ledger-schema.md`](reference/ledger-schema.md). The kickoff interview is [`reference/grilling.md`](reference/grilling.md). Templates are in `templates/`.

The script is `scripts/elih.py` (Python 3.9+, PyYAML); `--help` lists the subcommands.

## Procedure

### A. Kickoff (once per feature)

Fires on "set up elih", "kick off", or when a feature has requirements but no `elih/` directory.

1. Read the requirements and the repo, and look up every fact you can before asking anything. If a context-graph clone is reachable (ask once, or use `$LINT_LOCAL_REPOS_ROOT`), read its router, the relevant hub and the glossary first. Record each claim taken from a note as a `sources` row with the pillar or decision ids that will rest on it. A note is a pointer to verify; `verified` still needs the code or the system.
2. **Grill the human** per [`reference/grilling.md`](reference/grilling.md): invoke the `grilling` skill if it is available, else follow the vendored protocol, rooted in the seed tree on that page. Stop when the frontier is empty or the human says "enough".
3. **Land every answer in the ledger** using the landing table on that page, so nothing said in the interview stays only in chat. Unasked questions become `needs-you` rows. The chosen metaphor is frozen; a later rename needs a changelog row.
4. Run `elih.py init <dir> --feature <slug>` to scaffold, then fill `ledger.yaml`, `board.md` with pass 0 (today) and one pass per chunk, and one `chunks/<id>.md` per chunk. A section with nothing in it yet says "not built yet" and stays.
5. If `npx likec4` is available, write `model.c4` with the systems, the new deployable, and the stores. One `view` for the board context and one scoped `view` per chunk.
6. `elih.py lint` must pass. `elih.py render`. Show the human the board.

Done when: the human confirmed shared understanding (or stopped the grilling and the leftover frontier is on the board), the metaphor is frozen, every pillar has a state, lint passes, and the board renders.

### B. Per-run update (end of every run that changed code or plan)

1. For each chunk touched: update `stage`, `stage_note`, `paths`, `size`. A chunk's stage drops back to `tested` when its files change after the review that earned `reviewed`.
2. Every choice made this run becomes a ledger row: `assumed` if the agent chose and moved on, `recommended` if it wants the human's answer, `needs-you` if it cannot proceed. Cite the chunk. One sentence, plus a `why` when the ADR gate in the schema holds. New terms go in `vocabulary`; lint warns when prose uses a word the style guide avoids.
3. Every subagent handback: fold its decisions into the ledger under the main agent's name, and its findings into the chunk page.
4. Append changelog rows for what moved. Dated, one line each, in the human's words not the agent's.
5. Re-check every pillar against what was learned. A pillar found false becomes `invalidated` with the evidence, and the board shows it first. If the pillar rested on a `sources` row, that row becomes `contradicted` with `now` filled in; say so in the handoff, since the graph is now wrong and only the human can fix it.
6. `elih.py lint`, then `elih.py render`. The handoff ends with the board's "Blocked on you" list, verbatim, as its last section; the rest of the board stays on the board.

Done when: lint passes, the HTML is regenerated, and the handoff's last section is the blocked-on-you list.

### C. Ack (the human says "elih ack" or "/elih ack")

`elih.py ack` writes today's date to `feature.last_ack` and re-renders. The "since your last visit" panel then shows only changelog rows after that date.

### D. Orient (the human says "where are we", "I'm lost", "orient me")

The recap is `elih.py status`, which prints the board's L0 as text (blocked on you, changelog since ack, chunk stages, pillars). Paste that, then `elih.py render` and give the path. If the board is stale relative to the code (lint warns on `status_date` older than the last commit), run procedure B first.

### E. Brief the team

The briefing is the same HTML with L1 and L2 collapsed. The human presents the board and the stepper; questions go to the chunk pages.

### F. Dissolve (every chunk merged or deployed)

1. Resolve what can be resolved: every `recommended` and `assumed` row is either flipped to `approved` or `rejected` by the human, or stays and is listed as still open in the doc. Every `sources` row has a result.
2. `elih.py dissolve` writes `docs/<slug>.md` beside `elih/` (pass `-o` to put it elsewhere). It refuses while a chunk is short of `merged` unless `--partial` is given, and then the doc says which parts are unfinished.
3. Read the doc as a stranger. It describes what exists, in the present tense. Rewrite any sentence that only made sense during the build ("we decided", "the agent assumed"). Keep every Editor's note.
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

## Boundaries

The PR description, the design doc and the changelog are L2; elih links to them. When content would fit both a chunk page and a design doc, the design doc wins and the chunk page links to the section. Grilling runs once, at kickoff; later questions wait on the board as rows. The feature doc outlives the board and is written for a reader who never saw it.
