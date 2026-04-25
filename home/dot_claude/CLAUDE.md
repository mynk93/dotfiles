# Global preferences

## Background jobs and shells — prefer cmux

When spawning background jobs, long-lived shells, dev servers, log tails, or
any work you'd otherwise run via `Bash(run_in_background=true)` or the Agent
tool, use the **cmux** skill instead whenever `CMUX_SOCKET_PATH` is set.

**Why:** cmux output is visible to the user in a real pane they can watch
and interrupt. Hidden background jobs and subagent calls are opaque — the
user can't see progress or steer mid-flight.

**How to apply:**
- One pane (cmux workspace) per logical task. Name it (`--name "🤖 <role>"`)
  so it's legible in the sidebar.
- Multiple shells for the same task → multiple surfaces (splits) inside
  that pane via `cmux new-split`.
- Still fine to use plain `Bash` for quick one-shot commands (<30s, single
  round, no streaming needed). cmux is for anything the user would want
  to see or interact with.
- Follow the using-cmux skill's lifecycle rules (refresh-surfaces before
  read-screen, cleanup on completion, etc.).

## Cursor Bugbot — check after code PRs, skip for docs-only

Our PRs have Cursor Bugbot (`cursor[bot]`) configured to auto-review every
push. It's well-tuned and learns from in-thread replies. Treat its comments
as part of the review loop, not optional noise.

**When to wait for Bugbot:**
- PRs that change executable code, config, or CI. Worth the ~1–2 min wait.
- Schema / migration / infra changes where a subtle bug would be expensive.

**When to skip the Bugbot wait:**
- Docs-only PRs (`.md`, plan files, comments-only diffs). Bugbot won't
  find bugs in prose; waiting just delays the handoff.
- Asset-only PRs (fonts, images, audio) with no code.
- Trivial renames or path changes that a typechecker already validated.

Rule of thumb: **if a typechecker / lint / tests wouldn't have caught
something either, Bugbot probably won't either — skip the wait.** When
in doubt, spot-check with one manual `gh api .../comments` call but
don't block the workflow on it.

**After pushing or updating any code PR:**

1. Wait ~1–2 minutes for Bugbot to run, then fetch its comments:
   ```bash
   gh api repos/<org>/<repo>/pulls/<pr>/comments --paginate | \
     jq -r '.[] | select(.user.login == "cursor[bot]") | "[\(.path):\(.line // .original_line)]\n\(.body)"'
   ```
   (Top-level PR summary posts come through a different endpoint —
   `gh api repos/<org>/<repo>/issues/<pr>/comments` — fetch both if needed.)

2. Triage each finding:
   - **Fix** if it's a real bug (the default — Bugbot is accurate).
   - **Push back in-thread** if you disagree, with the reasoning. The bot
     learns from these replies, so the explanation directly improves future
     reviews.

3. Reply in the comment thread after fixing so Bugbot can close the loop and
   learn:
   ```bash
   gh api repos/<org>/<repo>/pulls/<pr>/comments/<comment_id>/replies \
     -f body="Confirmed and fixed in <sha>. <one-line explanation of the fix>"
   ```
   Prefer terse, informative replies (sha + what changed). That's what
   trains the bot — generic "thanks, fixed" is less useful.

4. Don't announce a PR as "done" or "ready to merge" until Bugbot comments
   are either resolved or explicitly argued with. Silent dismissal defeats
   the learning loop.

**When fixing on a stacked PR**, commit on the specific PR branch that
introduced the bug (not on the tip of the stack), then rebase downstream
branches onto the updated base. This keeps each PR self-contained and
preserves Bugbot's per-commit attribution.


## Response Style

- **DO NOT share timeline/effort estimates of development work**.  
  - Examples of things that should NOT be said
    - This will take 15 minutes
    - Its a 2-3 day effort
- **Lead with substance.** Skip validation phrases ("Great question!"). Provide the answer or solution immediately.
- **Match my technical level.** I provide context with specific tools, versions, and constraints. Respond at that level without simplification.
- **Be direct with constraints.** I state my constraints upfront (budget, time, hobby vs. professional). Factor these in without asking again.
- **Structure for iteration.** Use clear, numbered points or labeled sections so I can reference specific parts in follow-up corrections.
-  **Accept corrections cleanly.** When I say "not what I was looking for" and provide an alternative, adjust without defensive explanation.
- **First principles when exploring.** When I ask "what are my options" or mention "first principles," provide frameworks/categories before specific recommendations.
- **Omit negative framing.** State what something IS, not what it ISN'T. Skip "That's X, not Y" patterns—just give me X.
- **Brevity on confirmations.** When I say "looks good," acknowledge briefly and move to next step if there is one.
-
