---
name: pr-sanity
description: "Use for pr-sanity, cold-reading a PR, checking for AI smell, or a residue check before code review. Two fresh Sonnet readers inspect the PR body, problem source, docs, and diff; the main agent triages their observations with session context. Legibility and placement only, not implementation defects."
---

# pr-sanity

Two Sonnet sessions with no authoring history inspect the committed PR bundle. The cold reader narrates its understanding and records stumbles; the lint reader applies a fixed taxonomy. The main agent judges their observations with the authoring session's context and applies approved fixes.

## Review rules

- Exactly two readers, running Sonnet at high effort. One corrective retry per reader at most; no additional agents or automatic verification loop.
- Keep the initial readers independent. Their prompts contain no design summary, session history, or findings from the other reader. Each still inherits the repo's CLAUDE.md and hooks.
- Reader prompts and output contracts live in `prompts/cold.md` and `prompts/lint.md`. The helper loads them in place; neither prompt is copied into the worktree. Keep the lint taxonomy out of the cold reader's prompt.
- Legibility and placement only. Design, test adequacy, performance, security, and commit messages belong to code review.

## 1. Prepare

Use the shared helper for setup and process handling:

```bash
python3 ~/.claude/scripts/review_workflow.py --skill pr-sanity --repo "$PWD" prepare
```

It resolves the PR base, guards the merge-base, creates `.worktrees/pr-sanity` at committed HEAD, fetches closing issues, and writes the body, issue text, manifest, full diff with function context, and chunks sized for complete reads. It emits paths and preparation notes, not artifact contents. Read the notes; a missing problem source must appear in triage. If the repo provides `scripts/setup-worktree.sh`, follow its documented invocation before launch. Otherwise the helper links ignored `.venv` and `.env*` runtime files from the primary checkout.

Pre-PR preparation uses `.github/PR_BODY.md`, then `PR_BODY.md`; a missing body stops the run. An existing PR supplies its body and base, including a stacked PR's parent branch. If a committed plan is the problem source, pass `--plan <repo-relative-path>`. An empty diff still allows a body-and-problem-source review.

Dirty state stops preparation because reviewers see committed state only. If the user has chosen to exclude uncommitted changes, rerun with `--allow-dirty`. Existing runs are retained: collect or clean them up before preparing again. For offline/pre-PR preparation, use `--pre-pr`; `--target <branch>` selects an explicitly known base. These options do not bypass merge-base validation.

## 2. Launch and wait

```bash
python3 ~/.claude/scripts/review_workflow.py --skill pr-sanity --repo "$PWD" launch
```

With `CMUX_SOCKET_PATH` set, the helper creates cold and lint panes stacked to the right of the main pane, persists UUID handles, and launches both readers. It retains `--permission-mode auto` and `--strict-mcp-config` with zero MCP servers. `acceptEdits` stalls on read-only shell commands; keep `auto`.

Without cmux, add `--headless` and execute the launch as one background Bash task. That task owns both reader processes and returns when they finish. With cmux, start one background Bash waiter:

```bash
python3 ~/.claude/scripts/review_workflow.py --skill pr-sanity --repo "$PWD" wait --timeout 900
```

Completion requires the reviewer processes to exit, not just output files to appear. Wait on the background completion notification; inspect a screen only when diagnosing a stall. Use the using-cmux skill for screen inspection and interruption.

## 3. Validate and read

```bash
python3 ~/.claude/scripts/review_workflow.py --skill pr-sanity --repo "$PWD" collect
```

The helper checks the final CLI results and JSON structure, records usage, and returns paths and sizes for the original reports. It leaves their contents unchanged. It accepts missing lists or coverage notes when they clearly mean empty values. The main agent judges whether findings and narration are substantive.

Read both complete original JSON reports using [the report-reading instructions](../../references/review-artifacts.md). Preserve narration, all findings, full quotes, clean checks, and coverage notes. Validation and reading are separate operations; use the returned paths directly rather than generating a formatter or summary script.

If an output is malformed or lacks substantive content, write a correction naming the problem and run:

```bash
python3 ~/.claude/scripts/review_workflow.py --skill pr-sanity --repo "$PWD" retry --reader cold --prompt /absolute/path/to/correction.txt
```

Choose `cold` or `lint`. The helper appends the correction to that reader's original prompt and reuses its pane. In headless mode add `--headless` and run as a background Bash task. Wait, then collect again. One retry is enforced; report a second failure rather than starting another reader. Processes have exited before collection, so a partially written live report cannot accidentally consume the retry.

## 4. Triage and apply

1. Merge overlapping observations on the same artifact/file/line range, preserving both evidences. Map cold stumbles onto the taxonomy by judgement.
2. Compare the full cold narration with actual intent and the problem source. A misreading can reveal an under-explained body even when no stumble names it.
3. Judge each finding genuine or spurious using session context. Decide whether the content belongs in the repo, the PR discussion, or the working conversation. Choose the fix for each accepted finding.
4. Present accepted findings numbered as `N. [check] file:lines — "quote..." → intended fix`. Give a concise reason for each rejection, plus clean checks, coverage gaps, and missing problem sources.
5. Obtain approval before applying the proposed fixes unless that approval already exists in the session. Apply in the primary checkout or PR body, keeping GitHub prose unwrapped. Leave checkout changes uncommitted.

## 5. Cleanup

```bash
python3 ~/.claude/scripts/review_workflow.py --skill pr-sanity --repo "$PWD" cleanup
```

The helper closes the reader panes and removes the worktree after confirming process completion. `--archive <new-directory>` preserves original reports and usage before removal. `--abort` stops an unfinished run before cleanup. For failures or timeouts, consult [the lifecycle diagnostics](../../references/review-artifacts.md#lifecycle-diagnostics).

The pass ends after approved fixes. Start a new invocation to review them after committing.
