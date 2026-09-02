---
name: codex-review
description: "Use when the branch/PR should get an adversarial review from a different model — GPT-5.6 Sol at xhigh, driven through the Codex CLI (`codex exec`) in a visible cmux pane over a disposable review worktree. Bugs only: correctness, edge cases, races, data loss, security — no design or style commentary. The main agent triages the findings with session context, gates fixes on user approval, can interrogate the same review session, and optionally has the reviewer re-verify applied fixes. Triggers on 'codex-review', 'codex review', 'sol review', 'adversarial review', 'second opinion on this PR', 'have codex/gpt look at this', 'cross-model review'. Complements pr-sanity (legibility) and /code-review (same-model review)."
---

# codex-review

An adversarial bug hunt by a different model family. GPT-5.6 Sol gets an
isolated checkout with full context — diff, PR body, linked issues, the whole
tree at branch HEAD — and a mandate to break confidence in the change. The main
agent, which holds session context the reviewer lacks, triages the findings,
interrogates the same session where a finding is unclear, and applies approved
fixes.

The reviewer runs through the Codex CLI itself (`codex exec`), on its own
authentication and its own harness. Nothing routes through CLIProxyAPI or
`claudex`. Both the model *and* the harness differ from the authoring session,
which is a wider gap than sharing a harness could give.

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
   questions resume it by the thread id Codex assigns (soft cap ~3 rounds); no
   second reviewer, no Workflow tool, no dynamic agent spawning. Sol at xhigh on
   a real diff is the dominant cost of the run and bills straight to the Codex
   plan through the CLI's own credentials — that is the reason for the cap. The
   cap bounds *orchestrator* rounds, not the reviewer's own fan-out, and this is
   the one place where moving off `claudex` costs something. The old launch
   carried `--disallowedTools Agent` because a Claude Code reviewer inherits a
   subagent model and one observed run spawned ten Sol-at-xhigh subagents,
   exhausting the plan quota before a single finding was written. `codex exec`
   has no Agent tool and no equivalent flag, so that particular hole is closed
   by construction rather than by flag. The shell is still open, though: a
   reviewer running unsandboxed can invoke `codex`, `claude`, or `cmux`
   directly, and one did, spawning three sessions that billed elsewhere. The
   prompt's `<no_delegation>` block is now the *only* thing closing that path,
   where it used to be the second of two. Do not weaken it.
5. **Unrestricted reviewer, disposable worktree, gated fixes.** The reviewer
   runs with `--dangerously-bypass-approvals-and-sandbox`: it can execute code
   to *prove* a trigger rather than merely assert it, which measurably sharpens
   findings, and `codex exec` has no interactive approver to answer a mid-run
   prompt anyway. The flag is also forced by symmetry — `codex exec resume`
   accepts no `--sandbox`, so it is the one setting expressible on both the
   launch and every follow-up. Be precise about what that costs: there is no cage. Scratch files
   under the worktree die at cleanup, but the worktree sits at
   `.worktrees/codex-review` *inside* the repo, so the primary checkout is two
   levels up and reachable; worktrees share the ref store and object database,
   so a `git update-ref`, `branch -f`, or `tag` outlives `worktree remove`; and
   the prompt's `no network calls` is an instruction, not an enforcement. What
   actually protects the change under review is the gate on the other side —
   fixes happen only in the primary checkout, only after the user approves the
   triage report, and are left uncommitted.
6. **Prompts arrive as files, never as spliced text.** Every prompt is fed on
   stdin as `- < file`, `-` being Codex's explicit read-from-stdin form. Review
   prompts quote code (backticks, `$()`); text spliced into
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
- `codex` must be on PATH and authenticated — check with `codex login status`.
  It carries its own credentials under `~/.codex/`, so a working `claudex`
  proves nothing here and CLIProxyAPI being down is irrelevant to this skill.

### 2. Bundle context

- **Mode** — post-ready when `gh pr view --json number` succeeds for the current
  branch; pre-PR when it fails. Everything below branches on that one check.
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

# UUID handle: xhigh runs are long and surface:N refs renumber if workspaces close
REV=$(CMUX_QUIET=1 cmux --id-format uuids new-split right | awk '/^OK/{print $2}')
cmux rename-tab --surface "$REV" "codex-review"
cmux send --surface "$REV" "cd \"$WT\" && set -o pipefail; codex exec --json --model gpt-5.6-sol -c model_reasoning_effort=\"xhigh\" --dangerously-bypass-approvals-and-sandbox -o .review/out/result.md - < .review/prompt.md 2> .review/out/err.log | tee .review/out/raw.jsonl | jq -Rr --unbuffered 'fromjson? | if .type==\"item.completed\" then (.item.text // (\"→ \" + .item.type)) else empty end'; echo \$? > .review/out/rc\n"

echo "WT=$WT REV=$REV"   # carry these forward — see below
```

**Neither handle survives this step.** The Bash tool starts a fresh shell on
every call, so `$WT` and `$REV` are gone by step 5 — that is why the block echoes
them. Read them off that line and inline the literal values in every later step.
A step-5 waiter built with an empty `$WT` polls `/.review/out/rc`, never finds
it, and burns the full timeout before reporting a bogus stall.

There is no session id to pin here, and that is the one structural difference
from the `claudex` version: Codex mints its own thread id instead of accepting
one. It arrives as the very first line of the stream
(`{"type":"thread.started","thread_id":"…"}`), so step 5 lifts it out of
`raw.jsonl` once the run ends and persists it to `.review/out/sid` for the
follow-up steps.

Model and effort are pinned on the command line so a drifting
`~/.codex/config.toml` cannot silently swap the reviewer — that file carries its
own `model` and `model_reasoning_effort`, and it is an ordinary user config that
anything may rewrite. `set -o pipefail` (valid in both zsh and bash) makes the
trailing `$?` reflect `codex` rather than the last stage of the pipe — without it a proxy failure that kills the
reviewer instantly still records `rc=0`, because `jq` reads empty input and
exits clean.

The `jq` stage is the pane's live view. Codex wraps everything in
`item.completed` envelopes, so `.item.text // ("→ " + .item.type)` prints the
message when the item carries one and a typed arrow otherwise — which means the
filter never has to enumerate Codex's item types and cannot go blind when a new
one appears. `-Rr` with `fromjson?` is load-bearing, not style: a bare `jq` filter
*aborts* on the first unparseable line (exit 5) and stops emitting, and once it
exits the producer takes SIGPIPE on its next write, killing the run and
truncating `raw.jsonl` before the `result` envelope lands. Skipping bad lines
keeps the view cosmetic, which is the only way `raw.jsonl` is genuinely the
source of truth.

Without cmux, fall back to one background Bash task (`run_in_background`, never
bare `&`) running the same command. That fallback runs the whole procedure, not
just this step: there is no `$REV`, so steps 6 and 8 issue their `codex exec`
invocations as further background Bash tasks from `$WT`, and the liveness check
in step 5 is `raw.jsonl` growth rather than a pane read.

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
cat "$WT/.review/out/result.md"          # the review itself, written by -o

# The thread id, needed by steps 6 and 8. Persist it now.
SID=$(jq -r 'select(.type=="thread.started") | .thread_id' "$WT/.review/out/raw.jsonl" | head -1)
echo "$SID" > "$WT/.review/out/sid"

jq -r 'select(.item.type=="error") | "ERROR: \(.item.message)"' "$WT/.review/out/raw.jsonl"
jq -r 'select(.type=="turn.completed") | "in=\(.usage.input_tokens) out=\(.usage.output_tokens)"' "$WT/.review/out/raw.jsonl"
```

`-o` is why the review is a file rather than something to reassemble: Codex
writes the agent's final message there directly, so nothing has to reconstruct it
from the event stream. A missing or empty `result.md` means the run died before
finishing: read `.review/out/err.log`, the `error` items above, and `rc`
(meaningful only because step 4 set `pipefail`), then decide whether to
relaunch. If the waiter hits its 30m ceiling, judge liveness before killing
anything — `raw.jsonl` still growing (`wc -c` twice, ~30s apart) means the run is
slow, not hung, and the fix is to restart the waiter. `cmux refresh-surfaces`
then `cmux read-screen --surface "$REV" --lines 60` is the backup probe when the
file is static and you need to see whether the pane is at an auth prompt, a
crash, or a bare shell.

### 6. Follow-up questions (same session)

Where a finding is ambiguous, looks hallucinated, or needs a concrete trigger
spelled out, interrogate the session rather than guessing. Compose the question
with the Write tool, then resume by pinned id:

```bash
# Write tool → $WT/.review/followup-<n>.txt
cmux send --surface "$REV" "codex exec resume $SID --model gpt-5.6-sol -c model_reasoning_effort=\"xhigh\" --dangerously-bypass-approvals-and-sandbox -o .review/out/followup-<n>.md - < .review/followup-<n>.txt 2>> .review/out/err.log; echo \$? > .review/out/rc-followup-<n>\n"
```

`resume $SID` targets this exact thread. Codex also offers `resume --last`;
never use it here — it is the "most recent session" heuristic, and a concurrent
review in another repo would be picked up instead. No `--json` on follow-ups:
the answer lands in the `-o` file, and leaving stdout in Codex's human-readable
form keeps the pane legible. Wait on `rc-followup-<n>` with the same waiter, then
read `"$WT/.review/out/followup-<n>.md"` — the orchestrator's cwd is the primary
checkout, where no `.review/` exists, so the `$WT` prefix is required here even
though the pane's own redirects are relative. Keep questions surgical; after ~3
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
cmux send --surface "$REV" "codex exec resume $SID --model gpt-5.6-sol -c model_reasoning_effort=\"xhigh\" --dangerously-bypass-approvals-and-sandbox -o .review/out/verdict.md - < .review/verdict-prompt.txt 2>> .review/out/err.log; echo \$? > .review/out/rc-verdict\n"
```

Wait on `rc-verdict` with the step-5 waiter before reading
`"$WT/.review/out/verdict.md"` — the file does not exist until the round ends.
Then relay the verdicts. A `new concern` goes through triage judgment once — it
does not open another fix/re-verify loop; if it is real, report it for a
follow-up run.

### 9. Cleanup

`codex exec` exits on its own — the pane holds a plain shell afterward, so no
`/exit` ritual: `cmux close-surface --surface "$REV"`. To abort a run mid-flight,
`cmux send-key --surface "$REV" ctrl+c` first, then `TaskStop` the waiter: SIGINT
aborts the whole submitted line in interactive zsh, so `echo $? > rc` never runs
and an unkilled waiter would ride out its full 30 minutes on a run that is
already dead. Then:

```bash
git worktree remove --force .worktrees/codex-review
```

Everything the run wrote *as files* — `prompt.md`, `diff.patch`, `raw.jsonl`,
`sid`, every `followup-<n>` and `verdict` input and output, every `rc` sentinel,
and the reviewer's own scratch — lives under the worktree, so removing the
worktree disposes it in one step. Three things it does not dispose — the first
two per principle 5: anything the reviewer wrote *outside* the worktree, any ref
it created in the shared object store, and Codex's own transcript of the session,
which it records under `~/.codex/sessions/` and indexes in
`~/.codex/session_index.jsonl` regardless of the worktree. That transcript is
what makes `resume` work, so it has to outlive the run; delete it by hand if the
diff was sensitive. If a run looked like it wandered, `git reflog` and
`git branch --all` after cleanup are the check. Otherwise nothing lands in the
primary checkout except the applied fixes (left uncommitted); the step-8 patch
used a throwaway index, so the primary index is untouched. Single-shot by
design: for a fresh adversarial pass after committing fixes, rerun
`/codex-review`.
