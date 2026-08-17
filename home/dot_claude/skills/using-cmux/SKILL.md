---
name: using-cmux
description: Use whenever work should run in a visible terminal the user can watch, steer, or interrupt — dev servers, log tails, watch builds, background or long-running jobs, spawning Claude subagent workers, running investigations in parallel, or finding/controlling a Claude session in another terminal. When CMUX_SOCKET_PATH is set (you are inside cmux), prefer this over Bash(run_in_background) and over hidden Agent-tool subagents for anything the user might want to see. cmux is a native macOS terminal multiplexer (NOT tmux) with a socket-controlled CLI over workspaces, panes, and tabs. Also triggers on cmux, pane, workspace, split, tab, worker, subagent, "in parallel", "in another window/pane", "keep an eye on", "watch this", "run it on the side".
---

# Using cmux

cmux is a native macOS terminal with a socket-controlled CLI (`cmux`, in PATH). You create workspaces, split panes, send input, read output, and close them — programmatically, in a window the user is looking at. Delegation via cmux = **a visible terminal the user can watch and interrupt**, not a hidden coroutine.

If `CMUX_SOCKET_PATH` is set, default to cmux for anything watchable: background jobs you'd otherwise hide in `Bash(run_in_background)`, subagents you'd otherwise hide in the Agent tool, servers, tails, parallel investigations. Skip cmux only for quick one-shot commands (<30s, single round, nothing to watch).

| Task shape | Use |
|---|---|
| One-shot grep / file read / short command | Bash or Agent tool |
| Dev server, log tail, watch-build, any long-lived process | cmux pane |
| Multi-step investigation the user may want to watch or steer | cmux Claude worker |
| 2–4 related investigations in parallel | cmux workers, panes in one shared workspace |
| Independent new task | cmux worker in its own workspace |
| User says "in another pane/window", "on the side", "keep an eye on" | cmux |
| Find/inspect/kill a Claude session in a sibling terminal | cmux (tree + read-screen + send) |

## Mental model

```
window ⊃ workspace ⊃ pane ⊃ surface
```

- **Workspace** — sidebar entry; the tab-like unit holding one visible pane layout. Switching workspaces swaps the whole layout.
- **Pane** — a split region of the workspace. All panes of a workspace are visible at once.
- **Surface** — a tab *inside* a pane (each pane has its own tab strip). One surface per pane = no visible strip; several = stacked tabs, one visible at a time.

Refs (`workspace:N`, `pane:N`, `surface:N`) are **positional and renumber when things close** — never trust a stored ref across creates/closes. For handles held across topology changes, capture the UUID (`cmux list-workspaces --id-format both`, field 2) or re-resolve by name from `cmux tree` right before acting.

Orientation commands:

```bash
cmux identify         # your own workspace/pane/surface refs + socket path
cmux tree [--all]     # full topology; Claude sessions title their surface "✳ <task>"
cmux list-workspaces --id-format both   # refs + stable UUIDs + names
cmux docs api         # deep-dive CLI contract, fetchable via curl
```

## Placement and layout

**Which workspace?** A supporting shell for the task you're already doing (server, tail, scratch) goes in the *current* workspace as a split or tab. A new delegated task gets its *own* named workspace. Never dump unrelated shells into one workspace.

**Max 4 visible panes per workspace.** Standard arrangements:

```
2 shells         3 shells         4 shells
┌────┬────┐      ┌────┬────┐      ┌────┬────┐
│ A  │ B  │      │ A  │ B  │      │ A  │ B  │
│    │    │      ├────┴────┤      ├────┼────┤
└────┴────┘      │    C    │      │ C  │ D  │
                 └─────────┘      └────┴────┘
side-by-side     2 over 1         2×2 grid
```

Put wide-output shells (test runners, log tails) in the full-width bottom slot; interactive shells in the top pair. Deviate when the content demands it — these are defaults, not law.

**Beyond 4 shells — judgment call, two mechanisms:**

- **Tab-stack** (occasional reference: a second log, scratch shell, docs): add a surface to the most related pane — stays in the same workspace, hidden until clicked.
  ```bash
  cmux new-surface --workspace "$WS" --pane pane:N   # add tab; --focus true to show it
  cmux rename-tab --workspace "$WS" --surface <ref> "logs"
  ```
- **Sibling workspace** (things the user actively watches): spill panes 5+ into a second workspace named as a pair — `🤖 audit [1/2]`, `🤖 audit [2/2]`. Every shell keeps a real visible pane; the user switches like tabs.

Never squeeze 5+ visible panes into one workspace.

### Declarative layout (preferred when creating a workspace)

`new-workspace --layout '<json>'` builds the whole arrangement in one call. Nodes: `{"direction","split","children"}`; leaves: `{"pane":{"surfaces":[{"type":"terminal","command":"..."}]}}`.

- `"horizontal"` = children **side-by-side**; `"vertical"` = children **stacked** (opposite of vim/tmux jargon).
- `split` = fraction given to the first child (0.6 → first gets 60%).
- `command` is typed into the shell after init — same as sending it manually.
- Multiple surfaces in one pane = tabs; the *last* listed ends up selected.

The 3-shell template (verified):

```bash
CMUX_QUIET=1 cmux new-workspace --cwd "$(pwd)" --name "🤖 <role>" --layout '{
  "direction":"vertical","split":0.6,"children":[
    {"direction":"horizontal","split":0.5,"children":[
      {"pane":{"surfaces":[{"type":"terminal"}]}},
      {"pane":{"surfaces":[{"type":"terminal"}]}}]},
    {"pane":{"surfaces":[{"type":"terminal"}]}}]}'
```

4 shells = `vertical` root, two `horizontal` children. Then `cmux tree --workspace <ref>` to map the created surface refs.

### Imperative layout (adding to an existing workspace)

Split order matters — earlier splits keep full width/height, later splits subdivide one region:

```bash
# 2 shells: A|B                    # 3 shells: A|B over full-width C
cmux new-split right \             cmux new-split down  --workspace $WS --surface $S  # C
  --workspace $WS --surface $S     cmux new-split right --workspace $WS --surface $S  # A|B
# 4 shells: also split the bottom surface right
```

**Orchestrator + sidecar workers** — when the *current* session spawns workers into its own workspace and stays their control/triage pane, don't use the equal templates: the caller keeps its full-height pane on the left, workers stack in the right half.

```bash
# A │ B      A = caller (untouched, full height)
# A │ C      --id-format uuids ⇒ handles survive ref renumbering (rule 2)
B=$(CMUX_QUIET=1 cmux --id-format uuids new-split right | awk '/^OK/{print $2}')
C=$(CMUX_QUIET=1 cmux --id-format uuids new-split down --surface "$B" | awk '/^OK/{print $2}')
# each later split comes FROM the previous worker's surface — a bare
# `new-split down` would split the caller's column instead
```

A third worker splits down from `$C` (caller + 3 workers = the 4-pane cap).

## Critical rules (non-negotiable)

1. **Cross-workspace targeting: pass `--workspace` and `--surface` together.** `--surface surface:N` alone resolves only in your own workspace (errors otherwise). `--workspace workspace:N` alone targets that workspace's *focused* surface — ambiguous once it has multiple panes. In any multi-pane workspace, address every `send`/`send-key`/`read-screen` with both flags.
2. **Refs drift.** `workspace:N`/`surface:N` renumber when workspaces close. Re-resolve from `cmux tree` (or hold UUIDs) before any batch of sends — especially teardowns.
3. **Mid-string `\n` doesn't break lines.** `send "a\nb\n"` produces one line `a\nb` + Enter. Multi-line input = `send` each line, `send-key return` between, `send-key return` to submit.
4. **`send-key` is for named keys only** (`return`, `ctrl+c`, `escape`, `tab`, `up`, `down`). Bare characters like `q` for a pager go through `send "q"`; `send-key q` silently does nothing.
5. **Poll discipline.** `cmux refresh-surfaces` before every `read-screen` in a polling loop, and read ≥50 lines (`--lines 60`) — small reads miss the spinner and fake "idle".
6. **Never launch workers with `--dangerously-skip-permissions`** unless the user explicitly authorized it this session. Plain `claude` is the default.
7. **Always tear down.** Finished worker: `/exit` → `sleep 2` → `close-workspace` (re-resolve the ref first, see rule 2). Orphaned sessions burn tokens and clutter the sidebar.

## Claude worker lifecycle

```bash
# 1. Spawn (single worker; for 2–4 parallel workers use the layout pattern below)
WS=$(CMUX_QUIET=1 cmux new-workspace --cwd "$(pwd)" --name "🤖 <role>" | awk '/^OK/{print $2}')
cmux send --workspace "$WS" "claude\n"

# 2. First run in a new cwd may show a trust prompt — detect, ask the USER to approve, never auto-accept
sleep 3; cmux refresh-surfaces >/dev/null
cmux read-screen --workspace "$WS" --lines 60 | grep -qiE "do you trust" && echo "trust prompt — ask user"

# 3. Ready when the status line shows "? for shortcuts" (poll: sleep 2, refresh, read, ≤15 tries)

# 4. Prompt (multi-line per rule 3)
cmux send --workspace "$WS" "<prompt>\n"

# 5. Poll for completion: working markers present → still busy
#    sleep 4; refresh; read --lines 60; grep -qE "esc to interrupt|↓ [0-9]+ tokens" && continue

# 6. Collect: the ❯ input box bounds the final answer from below
result=$(cmux read-screen --workspace "$WS" --scrollback --lines 200)

# 7. Notify + teardown
cmux notify --title "Worker done" --body "<one-line summary>"
cmux send --workspace "$WS" "/exit\n"; sleep 2
cmux close-workspace --workspace "$WS"   # re-resolve ref if topology changed since spawn
```

## Parallel workers — shared workspace

Related parallel investigations live as **panes in one workspace** (layout templates above), so the user compares them side-by-side. **Cap: 4 concurrent Claude workers** unless the user explicitly authorizes more — each is real API cost. Truly independent tasks or overflow beyond 4 get their own `[i/N]` sibling workspace instead.

```bash
# Spawn 3 workers in one call — claude launches in every pane
WS=$(CMUX_QUIET=1 cmux new-workspace --cwd "$(pwd)" --name "🤖 audit workers" --layout '{
  "direction":"vertical","split":0.6,"children":[
    {"direction":"horizontal","split":0.5,"children":[
      {"pane":{"surfaces":[{"type":"terminal","command":"claude"}]}},
      {"pane":{"surfaces":[{"type":"terminal","command":"claude"}]}}]},
    {"pane":{"surfaces":[{"type":"terminal","command":"claude"}]}}]}' | awk '/^OK/{print $2}')

cmux tree --workspace "$WS"    # map surface refs → workers, e.g. surface:12 13 14

# Per-worker addressing from here on (rule 1: both flags):
cmux send --workspace "$WS" --surface surface:12 "<prompt A>\n"
cmux read-screen --workspace "$WS" --surface surface:13 --lines 60
```

Each pane's tab title auto-updates to the worker's current task (`✳ …`), so the strip stays legible without renaming. Poll round-robin over the surfaces (rule 5), collect each with `--scrollback`, then `/exit` every worker and close the one workspace.

## Long-lived side processes

Server, tail, watch-build: a split in the **current** workspace (or a tab-stacked surface if it's occasional-reference — see overflow judgment).

```bash
S=$(cmux new-split right | awk '/^OK/{print $2}')   # own workspace → refs resolve directly
cmux rename-tab --surface "$S" "dev-server"
cmux send --surface "$S" "npm run dev\n"
# later, on demand:
cmux read-screen --surface "$S" --lines 40
```

Read when there's a reason (user asks, build finished, task needs the server) — not in a tight loop. Before spawning a new pane, check `cmux list-pane-surfaces` for an idle shell (prompt-only screen) and reuse it.

## Notifications

```bash
cmux notify --title "Build done" --body "47/47 pass"          # in-app: badge + highlight
osascript -e 'display notification "Needs input" with title "Claude" sound name "Glass"'  # macOS banner
```

Fire **both** when a worker needs a human decision — you don't know which app the user is in.

## Sibling Claude sessions

"Kill/check/tell the Claude running in another workspace":

1. `cmux tree --all` — Claude surfaces are titled `✳ <task>` (or `◑/◐` variants).
2. `cmux read-screen --workspace <ref> --lines 20` (add `--surface` if multi-pane) — see what it's doing.
3. Kill cleanly: `send --workspace <ref> "/exit\n"` → `sleep 2`. Stuck: `send-key ctrl+c` first.
4. `close-workspace` only if nothing else lives there; otherwise `close-surface` just the Claude tab.

## Common mistakes

| Mistake | Fix |
|---|---|
| Trusting stored `workspace:N`/`surface:N` after closes | refs renumber — re-resolve via `tree`, or hold UUIDs (`--id-format both`) |
| `--surface surface:N` alone at another workspace | both flags: `--workspace workspace:N --surface surface:M` |
| `"vertical"` read as vim-style left/right | cmux vertical = stacked top/bottom; horizontal = side-by-side |
| Parsing `new-workspace` output with `awk '{print $2}'` | deprecation notice can precede — `CMUX_QUIET=1` + `awk '/^OK/{print $2}'` |
| 5+ panes crammed in one workspace | tab-stack the occasional shells, or spill to a `[2/2]` sibling workspace |
| `send "line1\nline2\n"` for multi-line | send + `send-key return` per line |
| `send-key q` to exit a pager | `send "q"` |
| `read-screen --lines 10` in a poll loop | `refresh-surfaces` first, `--lines 60` |
| TUI mis-rendered in a background workspace | PTY sizes settle on first render — select the workspace once |
| Expecting the first `surfaces[]` entry to be the visible tab | the last listed ends up selected; order accordingly or `--focus true` |
| `/exit` as the only cleanup | `/exit` → `sleep 2` → `close-workspace` |
| Unnamed workspaces | always `--name "🤖 <role>"` — sidebar legibility is the point |

## Environment

| Var | Meaning |
|---|---|
| `CMUX_SOCKET_PATH` | Set ⇒ you're inside cmux. Unset ⇒ fall back to Bash/Agent tool and say so. |
| `CMUX_WORKSPACE_ID` / `CMUX_SURFACE_ID` / `CMUX_TAB_ID` | Your own UUIDs — the defaults commands act on when flags are omitted. |
