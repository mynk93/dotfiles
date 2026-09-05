---
name: fable-review
description: "Use when the branch/PR should get an adversarial bug hunt from a fresh Fable 5.1 session — headless `claude` pinned to claude-fable-5-1 at high effort, in a visible cmux pane over a disposable review worktree. Bugs only: correctness, edge cases, races, data loss, security. No design or style commentary. The main agent triages findings with session context, gates fixes on user approval, can question the same review session, and closes the run by resuming that session to sign the applied fixes off. Triggers on 'fable-review', 'fable review', 'have fable review this', 'fresh-eyes review', 'second opinion from fable', 'adversarial fable pass'. Complements pr-sanity (legibility), /code-review (same-session review), and codex-review (cross-model review)."
---

# fable-review

An adversarial bug hunt by a fresh Fable 5.1 session. The reviewer gets an
isolated checkout with full context on disk (diff, PR body, linked issues, the
full tree at branch HEAD) and a mandate to disprove the change. It shares
nothing with the authoring session: no memory of the design discussion, no
investment in the approach. The main agent holds that session context, so it
triages the findings, questions the review session where a finding is unclear,
and applies approved fixes after the user signs off — then resumes that same
session to have the fixes signed off in turn, which is a required step rather
than an offer.

The reviewer runs through the plain `claude` CLI in headless mode with the
model pinned to `claude-fable-5-1`. No wrapper or proxy is involved.

## Principles

1. **Fresh eyes over shared history.** An authoring session accumulates trust
   in its own change; the reviewer starts with none. It reads the same files,
   holds none of the conversation, and its prompt forbids extending the change
   any benefit of the doubt. For coverage of a different model family's blind
   spots, use codex-review; the two runs are independent and both can be
   applied to the same branch.
2. **Bugs only.** Implementation defects: correctness, edge cases, races,
   partial failure, security, data loss. Design, style, naming, and approach
   commentary are out of scope. The prompt enforces the boundary and triage
   discards violations.
3. **Visible pane, one completion signal.** The run streams in a cmux split
   the user can watch. The result is read from `raw.jsonl`, never off the
   screen, and completion arrives through an `rc` sentinel file that a single
   background waiter watches; the orchestrator never polls in its own turns.
   `rc` says the run ended; `raw.jsonl` says how. Use the screen only to judge
   liveness, and even for that, whether `raw.jsonl` is still growing is the
   cheaper check.
4. **One session, resumable for the life of the run.** Exactly one review
   session per run, and every later exchange resumes it by its pinned session
   id — the reviewer that wrote a finding is the reviewer that judges the fix
   for it, holding its own evidence rather than re-deriving it. Follow-up
   questions (step 6) carry a soft cap of about 3 rounds; sign-off rounds
   (step 8) do not, because they end on the user's approval gate rather than on
   a convention. No second reviewer, no Workflow tool, no dynamic agent
   spawning. Fable 5.1 on a real diff is the dominant cost of the run, which is
   the reason for the follow-up cap. That cap bounds orchestrator rounds; the reviewer
   itself can still fan out through the Agent tool. Add `--disallowedTools
   Agent` to the launch when a run needs a hard ceiling rather than a
   convention.
5. **Unrestricted reviewer, disposable worktree, gated fixes.** The reviewer
   runs with `--permission-mode bypassPermissions` so it can execute code to
   prove a trigger instead of asserting one; executed triggers make sharper
   findings. Be clear-eyed about the containment: scratch files under the
   worktree die at cleanup, but the worktree sits at `.worktrees/fable-review`
   inside the repo, so the primary checkout is reachable two levels up;
   worktrees share the ref store and object database, so a `git update-ref`,
   `branch -f`, or `tag` survives `worktree remove`; and the prompt's "no
   network calls" is an instruction the model follows, without enforcement.
   The real protection is the gate on the other side: fixes land only in the
   primary checkout, only after the user approves the triage report, and stay
   uncommitted.
6. **Prompts arrive as files.** Every prompt is fed with `-p < file`. Review
   prompts quote code (backticks, `$()`), and text spliced into a `cmux send`
   string is shell-evaluated twice — once while composing, once in the pane —
   which corrupts the prompt and can execute embedded commands on the host.
   Redirection passes bytes through verbatim, so no prompt ever needs
   escaping.

The reviewer prompt lives at `prompts/review.md` in this skill's directory.
It is the single source of truth and is copied to `.review/prompt.md` in the
worktree at launch so the pane's redirect stays inside the disposable tree.

## Procedure

### 1. Preconditions

- Feature branch, off the default branch; abort if HEAD is detached or there
  is no `origin` remote.
- Committed state only: if `git status --porcelain` is dirty, warn that those
  changes will be skipped by the review and let the user decide whether to
  commit first.
- Ensure `.worktrees/` is in the repo's `.gitignore` (add it if missing).
- Remove a stale worktree from a previous run:
  `git worktree remove --force .worktrees/fable-review` — if the registration
  was already pruned, `git worktree prune && rm -rf .worktrees/fable-review`.
- `claude` must be on PATH. Auth problems surface in `err.log` and a non-zero
  `rc`, so no separate health check is needed.

### 2. Bundle context

- **Mode** — post-ready when `gh pr view --json number` succeeds for the
  current branch; pre-PR when it fails. Everything below branches on that one
  check.
- **PR body** — post-ready mode: `gh pr view --json body,baseRefName,number`;
  pre-PR mode: `.github/PR_BODY.md`, falling back to `PR_BODY.md`. A missing
  body still allows the run: the review proceeds on the diff alone; note the
  absence in the manifest and in the final report.
- **Linked issues** — parse the body for closing references (all GitHub
  keyword forms, `#N` or full URLs), fetch each with
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

git worktree add --detach .worktrees/fable-review HEAD
mkdir -p .worktrees/fable-review/.review/out
git diff "$BASE"..HEAD > .worktrees/fable-review/.review/diff.patch
cp ~/.claude/skills/fable-review/prompts/review.md \
   .worktrees/fable-review/.review/prompt.md
```

Write `.review/body.md` and `.review/issue.md` (when present), plus a slim
`.review/manifest.json`: `mode`, `repo`, `pr_number`, `branch`, `target`,
`merge_base`, `problem_source`. An empty diff is a reason to stop and tell the
user — there is nothing to attack.

### 4. Launch the reviewer pane

With cmux (`CMUX_SOCKET_PATH` set) — one sidecar split; the main session keeps
its full-height pane (using-cmux orchestrator pattern):

```bash
WT=<absolute path to .worktrees/fable-review>
SID=$(uuidgen | tr 'A-Z' 'a-z')   # pin it now; follow-ups resume this exact id
echo "$SID" > "$WT/.review/out/sid"

# UUID handle: review runs are long and surface:N refs renumber if workspaces close
REV=$(CMUX_QUIET=1 cmux --id-format uuids new-split right | awk '/^OK/{print $2}')
cmux rename-tab --surface "$REV" "fable-review"
cmux send --surface "$REV" "cd \"$WT\" && set -o pipefail; claude --model claude-fable-5-1 --effort high --session-id $SID --permission-mode bypassPermissions --output-format stream-json --verbose -p < .review/prompt.md 2> .review/out/err.log | tee .review/out/raw.jsonl | jq -Rr --unbuffered 'fromjson? | select(.type==\"assistant\") | .message.content[]? | if .type==\"text\" then .text elif .type==\"tool_use\" then \"→ \\(.name)\" else empty end'; echo \$? > .review/out/rc\n"

echo "WT=$WT SID=$SID REV=$REV"   # carry these forward — see below
```

**These three handles do not survive this step.** The Bash tool starts a fresh
shell on every call, so `$WT`, `$SID`, and `$REV` are gone by step 5; that is
why the block echoes them. Read them off that line and inline the literal
values in every later step. `$SID` is additionally persisted to
`.review/out/sid`, so a lost session id is recoverable as
`--resume "$(cat "$WT"/.review/out/sid)"`. A step-5 waiter built with an empty
`$WT` polls `/.review/out/rc`, never finds it, and burns the full timeout
before reporting a bogus stall.

Model and effort are pinned on the command line so a settings change or a
drifting default can never silently swap the reviewer. `set -o pipefail`
(valid in both zsh and bash) makes the trailing `$?` reflect `claude` rather
than the last stage of the pipe; without it, an API failure that kills the
reviewer instantly still records `rc=0`, because `jq` reads empty input and
exits clean.

The `jq` stage is the pane's live view: assistant text plus one arrow per tool
call. `-Rr` with `fromjson?` is required for correctness, beyond style. A bare
`jq` filter aborts on the first unparseable line (exit 5) and stops emitting,
and once it exits the producer takes SIGPIPE on its next write, killing the
run and truncating `raw.jsonl` before the `result` envelope lands. Skipping
bad lines keeps the view cosmetic, which is what lets `raw.jsonl` remain the
source of truth.

Without cmux, fall back to one background Bash task (`run_in_background`,
never bare `&`) running the same command. That fallback covers the whole
procedure, beyond this step: there is no `$REV`, so steps 6 and 8 issue their
`claude` invocations as further background Bash tasks from `$WT`, and the
liveness check in step 5 is `raw.jsonl` growth rather than a pane read.

### 5. Wait for completion — one background waiter, no poll loop

```bash
# Bash tool, run_in_background: exits the moment the run ends, either way.
# The harness re-invokes on exit, so this costs no orchestrator turns.
for i in $(seq 1 360); do [ -f "$WT/.review/out/rc" ] && exit 0; sleep 5; done
echo "review exceeded 30m"; exit 1
```

`rc` appears whether the reviewer succeeded, errored, or died, so silence is
never mistaken for progress. On the completion notification, read the outcome
from the envelope, never from the screen:

```bash
jq -r 'select(.type=="result") | "is_error=\(.is_error) subtype=\(.subtype) cost=\(.total_cost_usd // "n/a")"' "$WT/.review/out/raw.jsonl"
jq -r 'select(.type=="result") | .result' "$WT/.review/out/raw.jsonl"   # the review
```

No `result` line means the run died before finishing: read
`.review/out/err.log` and `rc` (meaningful only because step 4 set
`pipefail`), then decide whether to relaunch. If the waiter hits its 30m
ceiling, judge liveness before killing anything — `raw.jsonl` still growing
(`wc -c` twice, ~30s apart) means the run is slow and the fix is to restart
the waiter. `cmux refresh-surfaces` then
`cmux read-screen --surface "$REV" --lines 60` is the backup probe when the
file is static and you need to see whether the pane is at an auth prompt, a
crash, or a bare shell.

### 6. Follow-up questions (same session)

Where a finding is ambiguous, looks hallucinated, or needs a concrete trigger
spelled out, question the session rather than guessing. Compose the question
with the Write tool, then resume by pinned id:

```bash
# Write tool → $WT/.review/followup-<n>.txt
cmux send --surface "$REV" "claude --model claude-fable-5-1 --effort high --resume $SID --permission-mode bypassPermissions --output-format json -p < .review/followup-<n>.txt > .review/out/followup-<n>.json 2>> .review/out/err.log; echo \$? > .review/out/rc-followup-<n>\n"
```

`--resume $SID` targets this exact session — no cwd filtering, no
"most recent" heuristic, so concurrent reviews in other repos cannot be picked
up by mistake. Wait on `rc-followup-<n>` with the same waiter, then
`jq -r .result "$WT/.review/out/followup-<n>.json"` — the orchestrator's cwd
is the primary checkout, where no `.review/` exists, so the `$WT` prefix is
required here even though the pane's own redirects are relative. Keep
questions surgical; after ~3 rounds, carry any remaining ambiguity into triage
as reduced confidence instead of asking again.

### 7. Triage — main agent, with session context

1. Judge each finding genuine or spurious using session knowledge. Discard any
   that crossed the bugs-only boundary (design/style opinions). A finding
   whose trigger the reviewer *executed* deserves more weight than an asserted
   one; the transcript in `raw.jsonl` shows which is which.
2. Present the triage report and wait for approval before touching anything:
   - Accepted, numbered: `N. [severity] file:lines — what breaks → intended fix (one line)`
   - Rejected, collapsed: one line each with the reason.
   - Note the verdict line, anything from `## Solid` worth relaying, and a
     missing PR body/problem source if step 2 found none.
3. Apply approved fixes **in the primary checkout** — never inside the review
   worktree. Leave the changes uncommitted for the user to review and commit,
   then go to step 8: fixes are not the end of the run, sign-off is.

### 8. Sign-off — mandatory, same session, loops until clean

A run ends with the reviewer's verdict on the fixes, not with the fixes. This
step is not an offer. Once approved fixes are in the primary checkout, resume
the review session, show it the fix diff, and take a per-finding verdict — then
repeat until every accepted finding reads `addressed`.

Capture the *complete* fix: plain `git diff` omits staged and untracked
changes, so a fix that adds a file would re-verify as "not addressed". Diff
through a throwaway index so the primary index is never mutated (staging it
would be a commit footgun).

```bash
# From the primary checkout. R is the sign-off round, starting at 1 — every
# artefact below is round-numbered. Reuse one filename across rounds and the
# stale `rc-verdict` left by the previous round satisfies the step-5 waiter
# instantly, handing you round 1's verdict as though it were round 2's.
# R does not survive between Bash calls any more than $WT does; a loop that has
# already spanned several turns recovers it from disk rather than from memory:
#   ls "$WT"/.review/out/rc-verdict-* | wc -l   → rounds done, so R is that + 1
R=1

# Throwaway index = staged + unstaged + untracked, with no side effect on the
# real index. mktemp (never -u) creates the temp file securely; cp overwrites it
# with the real index; trap removes it on any exit.
TMP_INDEX=$(mktemp)
trap 'rm -f "$TMP_INDEX"' EXIT
cp "$(git rev-parse --git-dir)/index" "$TMP_INDEX"
GIT_INDEX_FILE="$TMP_INDEX" git add -A
GIT_INDEX_FILE="$TMP_INDEX" git diff --cached HEAD > "$WT/.review/fixes-$R.patch"
# Write tool → $WT/.review/verdict-prompt-$R.txt
#   "Fixes were applied for your accepted findings — see .review/fixes-<R>.patch.
#    For each finding F<n>: addressed / not addressed / new concern, one line each.
#    Read the files at their current state; do not judge from the patch alone."
cmux send --surface "$REV" "claude --model claude-fable-5-1 --effort high --resume $SID --permission-mode bypassPermissions --output-format json -p < .review/verdict-prompt-$R.txt > .review/out/verdict-$R.json 2>> .review/out/err.log; echo \$? > .review/out/rc-verdict-$R\n"
```

Fixes stay uncommitted and HEAD never moves, so each round's patch is
*cumulative* rather than the increment since the last round — the reviewer
always judges the change as it currently stands, which is what lets a later
round overturn an earlier `addressed`.

Wait on `rc-verdict-$R` with the step-5 waiter before reading
`jq -r .result "$WT/.review/out/verdict-$R.json"` — the file does not exist
until the round ends. Then relay every verdict line and act on it:

- **All `addressed`** — signed off. Say so, then go to cleanup.
- **Any `not addressed`** — the loop continues. Treat the reviewer's reason as
  a finding: judge it in triage, put the repairs you accept to the user for
  approval exactly as in step 7, apply them in the primary checkout, then rerun
  this step with `R` incremented. Nothing is applied without that approval, so
  the *user* ends the loop, not the reviewer — when a round repeats a finding
  the previous round already argued, say so plainly in the report so the choice
  between another lap and shipping the disagreement is an informed one.
- **`new concern`** — triage it once like any other finding. Accepted, it joins
  the next round's fixes; rejected, give the reason and let the loop close on
  whatever findings remain.

A run that reaches cleanup without a signed-off round is unfinished — report it
that way rather than as a completed review.

### 9. Cleanup

`claude -p` exits on its own — the pane holds a plain shell afterward, so no
`/exit` ritual: `cmux close-surface --surface "$REV"`. To abort a run
mid-flight, `cmux send-key --surface "$REV" ctrl+c` first, then `TaskStop` the
waiter: SIGINT aborts the whole submitted line in interactive zsh, so
`echo $? > rc` never runs and an unkilled waiter would ride out its full 30
minutes on a run that is already dead. Then:

```bash
git worktree remove --force .worktrees/fable-review
```

Everything the run wrote *as files* — `prompt.md`, `diff.patch`, `raw.jsonl`,
`sid`, every `followup-<n>` and round-numbered `fixes` / `verdict` input and
output, every `rc` sentinel, and the reviewer's own scratch — lives under the worktree, so
removing the worktree disposes it in one step. Two things it does not dispose,
per principle 5: anything the reviewer wrote *outside* the worktree, and any
ref it created in the shared object store. If a run looked like it wandered,
`git reflog` and `git branch --all` after cleanup are the check. Otherwise
nothing lands in the primary checkout except the applied fixes (left
uncommitted); the step-8 patch used a throwaway index, so the primary index is
untouched. Single-shot by design: for a fresh adversarial pass after
committing fixes, rerun `/fable-review`.
