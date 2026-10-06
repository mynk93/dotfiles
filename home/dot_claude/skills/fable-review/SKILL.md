---
name: fable-review
description: "Use for fable-review, an adversarial Fable bug hunt, fresh-eyes review, or a second opinion from Fable. A fresh claude-fable-5-1 session at high effort investigates implementation defects in an isolated checkout; the main agent triages findings and resumes the same reviewer for questions and fix sign-off."
---

# fable-review

A fresh Fable 5.1 session attacks the committed change, with executed evidence preferred over plausible reasoning. The main agent retains authoring context, judges the findings, applies approved fixes in the primary checkout, and resumes the same reviewer to verify them. Sign-off is required after fixes, not an optional offer.

## Boundaries

- Implementation defects only: correctness, edge cases, races, partial failure, security, and data loss. Discard opinions about design, style, naming, or test strategy.
- One initial session, pinned to `claude-fable-5-1` at high effort. Every question and verdict resumes its stored session ID. Follow-up questions have a soft cap of three rounds; sign-off continues through the user's approval gate until accepted findings are addressed.
- No second reviewer or dynamic orchestration. The reviewer retains its existing ability to use the Agent tool; this workflow does not reduce investigation effort or coverage.
- The reviewer receives a disposable checkout, PR body, issues, and complete diff, with no authoring history or design briefing. It still inherits the repo's CLAUDE.md and hooks.
- The helper retains `--permission-mode bypassPermissions` so the reviewer can execute triggers. The worktree contains scratch files, not process permissions: the primary checkout, shared Git refs, and host remain reachable. The prompt's no-network rule is an instruction, not enforcement.
- `prompts/review.md` is the review prompt and output contract. Prompts are passed through files/stdin, so quoted code and shell syntax remain literal.

## 1. Prepare

Run the maintained helper rather than reconstructing setup commands:

```bash
python3 ~/.claude/scripts/review_workflow.py --skill fable-review --repo "$PWD" prepare
```

It resolves the PR base, guards the merge-base, creates `.worktrees/fable-review` at committed HEAD, fetches closing issues, and writes the manifest, body/issue files when present, full diff, bounded diff chunks with an index, and the review prompt. It emits paths and preparation notes. Report a missing body or problem source; an empty diff stops the run. If the repo provides `scripts/setup-worktree.sh`, follow its documented invocation before launch. Otherwise the helper links ignored `.venv` and `.env*` runtime files from the primary checkout.

An existing PR supplies its base, including a stacked PR's parent branch. Pre-PR mode uses `.github/PR_BODY.md`, then `PR_BODY.md`, and permits a missing body. Pass `--plan <repo-relative-path>` when a committed plan is the problem source. Dirty state stops preparation; use `--allow-dirty` only after the user has chosen to review committed state. Existing runs are retained until collected or cleaned up. For offline/pre-PR preparation use `--pre-pr`, with `--target <branch>` when the base is explicitly known. Merge-base validation still applies.

## 2. Launch and wait

```bash
python3 ~/.claude/scripts/review_workflow.py --skill fable-review --repo "$PWD" launch
```

With `CMUX_SOCKET_PATH` set, the helper launches a streaming reviewer in a right-side cmux pane. It persists the session ID, pane UUID, process ID, and job paths in the worktree. The pane is for visibility; result envelopes and completion sentinels are authoritative.

Without cmux, add `--headless` and execute the launch as one background Bash task. With cmux, start one background Bash waiter:

```bash
python3 ~/.claude/scripts/review_workflow.py --skill fable-review --repo "$PWD" wait
```

Wait on its completion notification rather than polling in agent turns. A timeout preserves the run; inspect log growth and errors before deciding whether to extend the wait or abort. See [lifecycle diagnostics](../../references/review-artifacts.md#lifecycle-diagnostics) for failures. Use the using-cmux skill when screen inspection or interruption is needed.

## 3. Collect and read

```bash
python3 ~/.claude/scripts/review_workflow.py --skill fable-review --repo "$PWD" collect
```

The helper checks the process exit and result envelope, extracts the complete final review to a Markdown file, records usage, and returns its path and size. Read that entire file using [the artifact-reading procedure](../../references/review-artifacts.md), including the verdict, every finding, and Solid section. For evidence about an executed trigger, inspect the relevant transcript ranges; the collected verdict alone does not establish that a trigger ran.

## 4. Question ambiguous findings

Write surgical questions to a file, then resume the existing reviewer:

```bash
python3 ~/.claude/scripts/review_workflow.py --skill fable-review --repo "$PWD" followup --prompt /absolute/path/to/questions.txt
```

The helper reads the prompt literally, reuses the same pane/session, and allocates distinct round files and sentinels. In headless mode add `--headless` and use a background Bash task. Wait, collect, and read the original answer as in steps 2–3. After about three question rounds, carry unresolved ambiguity into triage as reduced confidence.

## 5. Triage and apply

1. Judge each finding genuine or spurious using session context. Discard bugs-only boundary violations. Executed triggers deserve more weight than asserted ones.
2. Present accepted findings numbered as `N. [severity] file:lines — what breaks → intended fix`. Give a concise reason for each rejection; include the verdict, relevant Solid observations, and missing body/problem-source notes.
3. Obtain approval before applying the proposed fixes unless that approval already exists in the session. Apply only in the primary checkout and leave changes uncommitted. Then perform sign-off.

## 6. Sign off against current files

Write the accepted finding IDs and their descriptions to a file. Use the helper for every sign-off round:

```bash
python3 ~/.claude/scripts/review_workflow.py --skill fable-review --repo "$PWD" signoff --findings /absolute/path/to/accepted-findings.txt
```

It captures HEAD plus staged, unstaged, and untracked changes through a throwaway index, writes a cumulative binary-capable fix patch, and refreshes the disposable checkout to that exact snapshot before resuming Fable. The primary index and checkout stay untouched; the review session ID and original HEAD remain fixed. Tracked reviewer scratch is replaced by the snapshot; noncolliding untracked scratch, logs, and runtime links survive. If primary HEAD moved, stop and start a fresh committed-state review.

The verdict verifies accepted findings and affected interactions against the current files. Newly exposed concerns retain the original evidence standard. Add `--headless` without cmux, then wait, collect, and read every verdict line.

- All `addressed`: report sign-off and clean up.
- Any `not addressed`: judge the reason, propose accepted repairs for approval, apply them, and run another sign-off round. Point out repeated disagreements so the user can decide whether to continue or ship with the disagreement.
- `new concern`: triage it once. Accepted concerns join the next round; rejected concerns receive a reason.

A run ended without reviewer sign-off after fixes is unfinished. Report it that way. Round allocation and fresh completion sentinels are the helper's responsibility; the agent does not reconstruct counters or recapture patches.

## 7. Cleanup

```bash
python3 ~/.claude/scripts/review_workflow.py --skill fable-review --repo "$PWD" cleanup
```

The helper confirms reviewer completion, closes its pane, and removes the worktree. `--archive <new-directory>` preserves collected reviews/verdicts and usage. `--abort` stops unfinished reviewer processes before cleanup; stop any separate background waiter too. Files or refs the reviewer wrote outside the disposable tree are not removed. Inspect reflog/branches if it appeared to wander.

A fresh adversarial review after committing fixes is a new invocation.
