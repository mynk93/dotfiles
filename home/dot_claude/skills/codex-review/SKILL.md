---
name: codex-review
description: "Use when the branch/PR should get an adversarial review from a different model — GPT-5.6 Sol at xhigh, driven through the Claude Code harness (`claudex`) in a visible cmux pane over an isolated review worktree. Bugs only: correctness, edge cases, races, data loss, security — no design or style commentary. The main agent triages the findings with session context, gates fixes on user approval, can interrogate the same review session, and optionally has the reviewer re-verify applied fixes. Triggers on 'codex-review', 'codex review', 'sol review', 'adversarial review', 'second opinion on this PR', 'have codex/gpt look at this', 'cross-model review'. Complements pr-sanity (legibility) and /code-review (same-model review)."
---

# codex-review

An adversarial bug hunt by a different model family. GPT-5.6 Sol gets an
isolated checkout with full context — diff, PR body, linked issues, the whole
tree at branch HEAD — and a mandate to break confidence in the change. The main
agent, which holds session context the reviewer lacks, triages the findings,
interrogates the same session where a finding is unclear, and applies approved
fixes.

The reviewer runs through `claudex` — the Claude Code harness pointed at Sol via
the local CLIProxyAPI (`~/.local/bin/claudex`). Same harness, different model
family: the adversarialism comes from the model, not the tooling.

## Principles

1. **Cross-model adversarialism is the product.** The authoring model shares
   blind spots with itself; a different model family attacks differently. Sol
   gets *full* context (this is not a cold read — pr-sanity owns that) but zero
   deference: its prompt forbids giving the change any benefit of the doubt.
2. **Bugs only.** Implementation defects — correctness, edge cases, races,
   partial failure, security, data loss. No design, style, naming, or approach
   commentary; the prompt enforces the boundary and triage discards violations.
3. **Visible pane, one completion signal.** The run streams in a cmux split the
   user can watch, but the *result* is never read off the screen and completion
   is never polled in a loop of the orchestrator's own turns. The pane writes an
   `rc` sentinel when the run ends; a single background waiter exits on that
   file and the harness re-invokes the orchestrator. `rc` says *the run ended*;
   `raw.jsonl` says *how it ended*. The screen is for judging liveness only, and
   even there `raw.jsonl` still growing is the cheaper signal.
4. **One session, fixed cost.** Exactly one review session per run. Follow-up
   questions resume it by its pinned session id (soft cap ~3 rounds); no second
   reviewer, no Workflow tool, no dynamic agent spawning. Sol at xhigh on a real
   diff is the dominant cost of the run and bills through the proxy to the Codex
   plan — that is the reason for the cap. The cap bounds *orchestrator* rounds,
   not the reviewer's own fan-out: `claudex` exports
   `CLAUDE_CODE_SUBAGENT_MODEL=gpt-5.6-sol`, so an unrestricted reviewer can
   spawn its own Sol-at-xhigh subagents. Add `--disallowedTools Agent` to the
   launch when a run needs a hard ceiling rather than a convention.
5. **Unrestricted reviewer, disposable worktree, gated fixes.** The reviewer
   runs in `--permission-mode auto` with no tool allowlist: it can execute code
   to *prove* a trigger rather than merely assert it, which measurably sharpens
   findings. Be precise about what that costs: there is no cage. Scratch files
   under the worktree die at cleanup, but the worktree sits at
   `.worktrees/codex-review` *inside* the repo, so the primary checkout is two
   levels up and reachable; worktrees share the ref store and object database,
   so a `git update-ref`, `branch -f`, or `tag` outlives `worktree remove`; and
   the prompt's `no network calls` is an instruction, not an enforcement. What
   actually protects the change under review is the gate on the other side —
   fixes happen only in the primary checkout, only after the user approves the
   triage report, and are left uncommitted.
6. **Prompts arrive as files, never as spliced text.** Every prompt is fed with
   `-p < file`. Review prompts quote code (backticks, `$()`); text spliced into
   a `cmux send` string is shell-evaluated twice — once composing, once in the
   pane — which corrupts the prompt and can execute embedded commands on the
   host. Redirection passes bytes through verbatim, so no prompt ever needs
   escaping.

The reviewer prompt lives at `prompts/review.md` in this skill's directory —
single source of truth, copied to `.review/prompt.md` in the worktree at launch
so the pane's redirect stays inside the disposable tree.

## Procedure

### 1. Preconditions

- Feature branch, not the default branch; abort if HEAD is detached or there is
  no `origin` remote.
- Committed state only: if `git status --porcelain` is dirty, warn that those
  changes won't be reviewed and let the user decide whether to commit first.
- Ensure `.worktrees/` is in the repo's `.gitignore` (add it if missing).
- Remove a stale worktree from a previous run:
  `git worktree remove --force .worktrees/codex-review` — if the registration
  was already pruned, `git worktree prune && rm -rf .worktrees/codex-review`.
- `claudex` must be on PATH. It self-checks the proxy and exits non-zero with a
  clear message if CLIProxyAPI is down, so no separate health check is needed.

### 2. Bundle context

- **PR body** — post-ready mode: `gh pr view --json body,baseRefName,number`;
  pre-PR mode: `.github/PR_BODY.md`, falling back to `PR_BODY.md`. Unlike
  pr-sanity, a missing body does not stop the run — the review proceeds on the
  diff alone; note the absence in the manifest and in the final report.
- **Linked issues** — parse the body for closing references (all GitHub keyword
  forms, `#N` or full URLs), fetch each with
  `gh issue view <N|URL> --json title,body,url`, render all into
  `.review/issue.md` (one section per issue: title, URL, body).

### 3. Build the review worktree

```bash
# TARGET: baseRefName in post-ready mode; otherwise the default branch.
git fetch origin "$TARGET"        # stale refs inflate the diff; if offline, warn and continue

# Guard the merge-base: an empty BASE turns `git diff "$BASE"..HEAD` into
# `git diff ..HEAD` (HEAD..HEAD → empty, exit 0), which the empty-diff check
# below would misread as "nothing to attack". Shallow clones and offline runs
# (no origin/$TARGET) hit this.
if ! BASE=$(git merge-base "origin/$TARGET" HEAD) || [ -z "$BASE" ]; then
  echo "no merge-base with origin/$TARGET — deepen the clone or fetch $TARGET, then retry"
  exit 1
fi

git worktree add --detach .worktrees/codex-review HEAD
mkdir -p .worktrees/codex-review/.review/out
git diff "$BASE"..HEAD > .worktrees/codex-review/.review/diff.patch
cp ~/.claude/skills/codex-review/prompts/review.md \
   .worktrees/codex-review/.review/prompt.md
```

Write `.review/body.md` and `.review/issue.md` (when present), plus a slim
`.review/manifest.json`: `mode`, `repo`, `pr_number`, `branch`, `target`,
`merge_base`, `problem_source`. An empty diff is a reason to stop and tell the
user — there is nothing to attack.

### 4. Launch the reviewer pane

With cmux (`CMUX_SOCKET_PATH` set) — one sidecar split; the main session keeps
its full-height pane (using-cmux orchestrator pattern):

```bash
WT=<absolute path to .worktrees/codex-review>
SID=$(uuidgen | tr 'A-Z' 'a-z')   # pin it now; follow-ups resume this exact id

# UUID handle: xhigh runs are long and surface:N refs renumber if workspaces close
REV=$(CMUX_QUIET=1 cmux --id-format uuids new-split right | awk '/^OK/{print $2}')
cmux rename-tab --surface "$REV" "codex-review"
cmux send --surface "$REV" "cd \"$WT\" && claudex --model gpt-5.6-sol --effort xhigh --session-id $SID --permission-mode auto --output-format stream-json --verbose -p < .review/prompt.md 2> .review/out/err.log | tee .review/out/raw.jsonl | jq -r --unbuffered 'select(.type==\"assistant\") | .message.content[]? | if .type==\"text\" then .text elif .type==\"tool_use\" then \"→ \\(.name)\" else empty end'; echo \$? > .review/out/rc\n"
```

Model and effort are pinned on the command line so neither a settings change nor
a drifting `claudex` default can silently swap the reviewer. The `jq` stage is
the pane's live view — assistant text plus one arrow per tool call; `raw.jsonl`
is the untransformed source of truth, so a jq hiccup can cost readability but
never the review. Without cmux, fall back to one background Bash task
(`run_in_background`, never bare `&`) running the same command.

### 5. Wait for completion — one background waiter, no poll loop

```bash
# Bash tool, run_in_background: exits the moment the run ends, either way.
# The harness re-invokes on exit, so this costs no orchestrator turns.
for i in $(seq 1 360); do [ -f "$WT/.review/out/rc" ] && exit 0; sleep 5; done
echo "review exceeded 30m"; exit 1
```

`rc` appears whether the reviewer succeeded, errored, or died, so silence is
never mistaken for progress. On the completion notification, read the outcome
from the envelope — not from the screen:

```bash
jq -r 'select(.type=="result") | "is_error=\(.is_error) subtype=\(.subtype) cost=\(.total_cost_usd // "n/a")"' "$WT/.review/out/raw.jsonl"
jq -r 'select(.type=="result") | .result' "$WT/.review/out/raw.jsonl"   # the review
```

No `result` line means the run died before finishing: read `.review/out/err.log`
and `rc`, and check pane liveness with `cmux refresh-surfaces` then
`cmux read-screen --surface "$REV" --lines 60` before deciding whether to relaunch.
If the waiter hits its 30m ceiling while the pane is still emitting tool calls,
the run is slow, not hung — restart the waiter rather than killing the session.

### 6. Follow-up questions (same session)

Where a finding is ambiguous, looks hallucinated, or needs a concrete trigger
spelled out, interrogate the session rather than guessing. Compose the question
with the Write tool, then resume by pinned id:

```bash
# Write tool → $WT/.review/followup-<n>.txt
cmux send --surface "$REV" "claudex --model gpt-5.6-sol --effort xhigh --resume $SID --permission-mode auto --output-format json -p < .review/followup-<n>.txt > .review/out/followup-<n>.json 2>> .review/out/err.log; echo \$? > .review/out/rc-followup-<n>\n"
```

`--resume $SID` targets this exact session — no cwd filtering, no "most recent"
heuristic, so concurrent reviews in other repos cannot be picked up by mistake.
Wait on `rc-followup-<n>` with the same waiter, then
`jq -r .result .review/out/followup-<n>.json`. Keep questions surgical; after ~3
rounds, carry any remaining ambiguity into triage as reduced confidence instead
of asking again.

### 7. Triage — main agent, with session context

1. Judge each finding genuine or spurious using session knowledge. Discard any
   that crossed the bugs-only boundary (design/style opinions). A finding whose
   trigger the reviewer *executed* deserves more weight than an asserted one —
   the transcript in `raw.jsonl` shows which is which.
2. Present the triage report and wait for approval before touching anything:
   - Accepted, numbered: `N. [severity] file:lines — what breaks → intended fix (one line)`
   - Rejected, collapsed: one line each with the reason.
   - Note the verdict line, anything from `## Solid` worth relaying, and a
     missing PR body/problem source if step 2 found none.
3. Apply approved fixes **in the primary checkout** — never inside the review
   worktree. Leave the changes uncommitted for the user to review and commit.

### 8. Offer re-verification

After fixes are applied, offer it (don't just do it): send the fix diff back to
the same session for a verdict, one round only. Capture the *complete* fix —
plain `git diff` omits staged and untracked changes, so a fix that adds a file
would re-verify as "not addressed". Diff through a throwaway index so the
primary index is never mutated (staging it would be a commit footgun).

```bash
# From the primary checkout. Throwaway index = staged + unstaged + untracked,
# with no side effect on the real index. mktemp (never -u) creates the temp file
# securely; cp overwrites it with the real index; trap removes it on any exit.
TMP_INDEX=$(mktemp)
trap 'rm -f "$TMP_INDEX"' EXIT
cp "$(git rev-parse --git-dir)/index" "$TMP_INDEX"
GIT_INDEX_FILE="$TMP_INDEX" git add -A
GIT_INDEX_FILE="$TMP_INDEX" git diff --cached HEAD > "$WT/.review/fixes.patch"
# Write tool → $WT/.review/verdict-prompt.txt
#   "Fixes were applied for your accepted findings — see .review/fixes.patch.
#    For each finding F<n>: addressed / not addressed / new concern, one line each."
cmux send --surface "$REV" "claudex --model gpt-5.6-sol --effort xhigh --resume $SID --permission-mode auto --output-format json -p < .review/verdict-prompt.txt > .review/out/verdict.json 2>> .review/out/err.log; echo \$? > .review/out/rc-verdict\n"
```

Relay the verdicts. A `new concern` goes through triage judgment once — it does
not open another fix/re-verify loop; if it is real, report it for a follow-up
run.

### 9. Cleanup

`claudex -p` exits on its own — the pane holds a plain shell afterward, so no
`/exit` ritual: `cmux close-surface --surface "$REV"`. To abort a run mid-flight,
`cmux send-key --surface "$REV" ctrl+c` first. Then:

```bash
git worktree remove --force .worktrees/codex-review
```

Everything the run wrote — `prompt.md`, `diff.patch`, `raw.jsonl`, every
`followup-<n>` and `verdict` input and output, every `rc` sentinel, and anything
the reviewer itself created while running unrestricted — lives under the
worktree, so removing the worktree disposes all of it in one step. Nothing lands
in the primary checkout except the applied fixes (left uncommitted); the step-8
patch used a throwaway index, so the primary index is untouched. Single-shot by
design: for a fresh adversarial pass after committing fixes, rerun
`/codex-review`.
