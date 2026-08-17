---
name: pr-sanity
description: "Use before opening a PR (or after marking one ready) to strip AI-agent smell from the branch — a cold-reader sanity pass over the PR body, linked GitHub issue, changed docs, and diff. Runs a fixed two-reader pipeline (unprimed cold read + checklist lint) as Sonnet sessions in visible cmux panes over a review worktree, then triages their findings with session context and applies approved fixes. Triggers on 'pr-sanity', 'sanity check the PR', 'cold read this PR', 'check for AI smell', 'residue check'. Precursor to full code review — mechanical legibility checks only, no design critique."
---

# pr-sanity

A pre-review pass that removes AI-agent smell from a branch before anyone else reads it. Two fresh-context Sonnet readers consume the PR bundle cold and report structured findings; the main agent — which holds the session context the readers deliberately lack — judges what is genuine and how each accepted finding gets fixed. Runs before `gh pr create`, or on an existing PR after it is marked ready.

## Principles

1. **Coldness is the product.** The authoring session cannot detect its own residue because the residue is legible to it. Never brief the readers — no summary of the PR, no session context in their launch commands. They receive only a checkout and a bundle, and read everything themselves. (Accepted residual: readers still load the repo's CLAUDE.md and hooks at branch HEAD; everything else stays cold.)
2. **Predetermined pipeline, fixed cost.** The path is a fixed DAG: build bundle → two readers in parallel → triage → apply. Exactly two reader sessions, one corrective retry each at most, no dynamic orchestration that can spawn agents open-endedly. Do NOT use the Workflow tool or spawn additional agents beyond the two readers.
3. **Readers report; the main agent judges.** The output contracts have no fix field and the prompts forbid remediation language. Deciding what is genuine and how it gets fixed is the main agent's job, done with session context.
4. **Visible workers.** When `CMUX_SOCKET_PATH` is set, each reader runs in its own cmux split in the current workspace so the user can watch and interrupt. Fall back to background `claude -p` runs only when cmux is absent.
5. **Persistence-layer lens for triage.** Every artifact has a home layer — repo (permanent), PR (review-time), session (ephemeral). Most genuine findings are content promoted one layer too persistent; the fix is usually demoting it or adding the context that earns its layer.
6. **Boundary.** Legibility and placement only. Design quality, over-engineering, defensive code, test adequacy, performance, security, and commit messages belong to the full code review that follows.

The reader contracts (prompts + output JSON shapes) live in `prompts/cold.md` and `prompts/lint.md` in this skill's directory — single source of truth. They are read in place at launch and NEVER copied into the worktree: the cold reader must have no way to find the lint taxonomy, and its prompt must never contain it — priming it would turn the cold read into a second lint and kill its ability to catch unknown-unknowns.

## Procedure

### 1. Preconditions

- Must be on a feature branch, not the default branch. Abort with a clear message if HEAD is detached or there is no `origin` remote — the pipeline needs both.
- The pass reads committed state only. If `git status --porcelain` shows uncommitted changes, warn the user that those changes will not be seen, and let them decide whether to commit first.
- Ensure `.worktrees/` is in the repo's `.gitignore` (add it if missing).
- Remove any stale worktree from a previous run: `git worktree remove --force .worktrees/pr-sanity` — if that fails because the registration was already pruned, `git worktree prune && rm -rf .worktrees/pr-sanity`.

### 2. Resolve the PR body and the problem source

- **Post-ready mode** — if a PR exists for the branch (`gh pr view` succeeds): fetch `gh pr view --json body,baseRefName,number`.
- **Pre-PR mode** — read `.github/PR_BODY.md`, falling back to `PR_BODY.md` at the repo root. If neither exists, stop and tell the user to draft the body first (the `pro-pr-description` skill can produce it). Do not improvise a body.
- **Problem source** — the source of truth for what is being solved is a linked GitHub issue or a committed plan doc; one should always exist:
  - Parse the body for closing references, case-insensitively and in all GitHub keyword forms — `close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved` followed by `#N` or a full issue URL.
  - Fetch each with `gh issue view <N or URL> --json title,body,url` — pass URLs through verbatim so cross-repo references resolve against the right repo.
  - Render ALL closing issues into `.review/issue.md`, one section each: `# #N — <title>`, the URL, then the body.
  - If no issue is linked, look for a plan doc the body references that exists in the repo; record its path in the manifest (it is already in the worktree).
  - If neither exists, proceed, but flag it prominently in the triage report — a PR with no problem source is itself a finding for the user.

### 3. Build the review worktree

```bash
# TARGET: baseRefName in post-ready mode; otherwise the default branch
# (git symbolic-ref --short refs/remotes/origin/HEAD, falling back to main, then master).
# Diffing a stacked PR against the default branch would sweep in every upstream PR's changes.
git fetch origin "$TARGET"   # stale remote refs inflate the diff with phantom changes; if offline, warn and continue

# Guard the merge-base: an empty BASE makes `git diff "$BASE"..HEAD` collapse to
# `git diff ..HEAD` (empty, exit 0), silently degrading the whole pass to a
# body-only read of a branch that actually has changes. Shallow clones and
# offline runs (no origin/$TARGET) hit this — distinct from a legitimately empty
# diff, which is fine and still degrades to body-and-issue-only by design.
if ! BASE=$(git merge-base "origin/$TARGET" HEAD) || [ -z "$BASE" ]; then
  echo "no merge-base with origin/$TARGET — deepen the clone or fetch $TARGET, then retry"
  exit 1
fi

git worktree add --detach .worktrees/pr-sanity HEAD
mkdir -p .worktrees/pr-sanity/.review/out
git diff "$BASE"..HEAD > .worktrees/pr-sanity/.review/diff.patch
```

Write the PR body to `.review/body.md` — pre-PR: copy the body file; post-ready: write the `body` field fetched in step 2. Add `.review/issue.md` from step 2 when issues are linked.

Then write `.review/manifest.json`:

```json
{
  "mode": "pre_pr | post_ready",
  "repo": "<owner/name, parsed from git remote get-url origin>",
  "pr_number": 0,
  "branch": "<branch>",
  "target": "<TARGET>",
  "merge_base": "<sha>",
  "problem_source": { "type": "issue | plan_doc | none", "refs": ["<issue URLs or doc path>"] },
  "files": [{ "path": "...", "additions": 0, "deletions": 0 }]
}
```

(`files` comes from `git diff --numstat`; binary files report `-` there — record those as `{ "path": "...", "binary": true }`. `repo` and `pr_number` are recorded so nothing downstream has to guess them.) An empty diff is fine — the pass degrades to a body-and-issue-only read.

The worktree gives the readers the full checkout at branch HEAD — needed to judge comment density and naming against each file's existing idiom — with no network calls. It also contains any stray write a reader might make, since the whole tree is discarded after the run.

### 4. Launch the readers (visible panes)

With cmux (`CMUX_SOCKET_PATH` set) — the main session keeps its full-height pane on the left; the two readers stack in the right half:

```
main │ cold
main │ lint
```

```bash
WT=<absolute path to .worktrees/pr-sanity>
PROMPTS=~/.claude/skills/pr-sanity/prompts

# --id-format uuids: readers run for minutes, and surface:N refs renumber if any
# workspace closes meanwhile — UUIDs stay valid for correction and cleanup
COLD=$(CMUX_QUIET=1 cmux --id-format uuids new-split right | awk '/^OK/{print $2}')
# split down FROM the cold pane — a bare `new-split down` would split the main pane's column
LINT=$(CMUX_QUIET=1 cmux --id-format uuids new-split down --surface "$COLD" | awk '/^OK/{print $2}')

for entry in "cold:$COLD" "lint:$LINT"; do
  pass="${entry%%:*}"; SURF="${entry#*:}"
  cmux rename-tab --surface "$SURF" "pr-sanity: $pass"
  # --permission-mode auto, NOT acceptEdits: the reader runs read-only commands
  # (grep/git/bash reads) constantly; acceptEdits pauses on every one and stalls
  # the pane while the orchestrator blocks on the output file. See note below.
  cmux send --surface "$SURF" "cd \"$WT\" && claude --model sonnet --effort high --permission-mode auto --strict-mcp-config \"\$(cat $PROMPTS/$pass.md)\"\n"
done
```

`$COLD`/`$LINT` are the per-pass surface refs for polling, correction, and cleanup. If a trust prompt appears in a pane (fresh worktree path), tell the user to approve it there.

Both launch flags exist to keep a reader from stalling mid-run while the orchestrator blocks on its output file:

- **`--permission-mode auto`, never `acceptEdits`.** acceptEdits looks like the natural fit for a reader whose only write is one output file — that is exactly the trap. It auto-accepts *edits* but still pauses on every *command*, and the readers run read-only commands (grep, git, bash file reads) constantly; each one would freeze the pane waiting on an approval no one is watching, and the orchestrator would time out on a file that never arrives. `auto` approves both edits and commands, so the reader runs unattended to the finish. Read-only discipline is enforced by the reader's *prompt* (its only permitted write is the output file), not by the permission mode, so `auto`'s broader approval is safe here. Do not "tighten" this to `acceptEdits`.
- **`--strict-mcp-config` with no `--mcp-config`** loads zero MCP servers — the readers need none, and configured servers otherwise trigger a consent prompt at launch.

Without cmux, fall back to headless runs — one background Bash task per reader (`run_in_background`, never bare `&` inside a single call, so each has a handle you can inspect and kill). Same flags as the pane launch, for the same reasons:

```bash
cd "$WT" && claude -p "$(cat ~/.claude/skills/pr-sanity/prompts/cold.md)" --model sonnet --effort high --permission-mode auto --strict-mcp-config
```

### 5. Wait on outputs, not screens

Completion is file-based: poll for `.review/out/cold.json` and `.review/out/lint.json` (every ~20s, give up around 15 minutes). If a reader times out: in cmux, `cmux refresh-surfaces` then `cmux read-screen` its pane to diagnose — the user can see the same thing; in fallback mode, check the task's output, and kill it before any cleanup touches the worktree.

### 6. Collect and validate

Parse each JSON. A file that fails to parse may simply be mid-write — re-poll until its mtime is stable (up to ~1 minute) before judging it malformed, so the race doesn't burn the retry. Then validate leniently against the shapes in `prompts/*.md`: required keys present, `check`/`kind`/`artifact`/`confidence` values from their enums, quotes non-empty, narration a real briefing rather than a placeholder. Judgement beats rigidity — a missing key that is obviously an empty list is an empty list, not a retry. If an output is genuinely malformed or degenerate, correct it ONCE: in cmux, send that pane one message naming what is wrong; in fallback mode, one fresh `claude -p` run with the correction appended to the prompt. If it fails again, report the failure to the user rather than looping.

### 7. Triage — main agent, with session context

1. **Merge and dedupe** the two result sets: same artifact + same file + overlapping line ranges → one finding, both evidences kept.
2. **Map cold stumbles** onto the taxonomy (an `unanchored_reference` is usually a context_leak or conversational_residue; `seems_out_of_place` often internal_consistency or scaffolding; `other` maps by judgement).
3. **Compare the cold narration against actual intent** — and against the issues in `.review/issue.md`. A misreading, not just a stumble, is itself a finding: the body under-explains whatever was misread.
4. **Judge each finding** genuine or spurious using session knowledge, and decide the fix for each accepted one (delete / move to PR description / move to a future PR comment / rewrite in place / add missing context).
5. **Present the triage report** and wait for approval before touching anything:
   - Accepted, numbered: `N. [check] file:lines — "quote…" → intended fix (one line)`
   - Rejected, collapsed: one line each with the reason.
   - Note `clean_checks`, any `coverage_notes` gaps, and a missing problem source if step 2 found none.
6. **Apply approved fixes in the primary checkout** — code changes to the working tree, body changes to the body file (or via `gh pr edit` in post-ready mode; PR-body prose is never hard-wrapped, per GH-6). Never edit inside the review worktree. Leave the resulting changes uncommitted for the user to review and commit.

### 8. Cleanup

For each reader pane: `cmux send --surface <ref> "/exit\n"`, wait ~2s, then `cmux close-surface --surface <ref>`. In fallback mode, confirm both background tasks have exited (kill any survivor). Then:

```bash
git worktree remove --force .worktrees/pr-sanity
```

Single-shot by design: no automatic verify loop. To confirm the fixes read clean, the user reruns `/pr-sanity` after committing.
