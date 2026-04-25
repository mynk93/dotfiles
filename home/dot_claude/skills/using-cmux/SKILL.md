---
name: using-cmux
description: Use when orchestrating cmux (the native macOS terminal multiplexer, NOT tmux) — spawning visible subagents in panes/workspaces, running work in parallel, driving sibling terminal sessions, watching dev servers or log tails, or any task where a visible/steerable worker beats a hidden Agent-tool call. Also triggers when CMUX_SOCKET_PATH is set (running inside cmux) or the user mentions cmux, subagent, worker, "in parallel", "in another pane/window", or asks to find/control a Claude session running in a different terminal.
---

# Using cmux

cmux is a native macOS terminal with a socket-controlled CLI. You control workspaces, panes, and surfaces programmatically — spawn them, send input, read output, close them. The CLI lives at `cmux` (in PATH).

The paradigm shift: delegation via cmux = **a visible terminal the user can watch and interrupt**, not a hidden coroutine. Use it when visibility, parallelism, or steerability matters. Don't use it for quick one-shot greps — the built-in Agent tool is faster and cheaper for those.

## When to use this skill vs. the built-in Agent tool

| Task shape | Use |
|---|---|
| Single-round grep / file read / one-shot lookup | **Agent tool** (built-in) |
| Multi-step investigation the user wants to watch | cmux subagent |
| 2+ investigations you want to run in parallel | cmux subagents (one per workspace) |
| Dev server, log tail, watch-build, long-lived process | cmux pane (only option that works) |
| Work the user may want to steer mid-flight | cmux subagent |
| User explicitly says "in another pane/window/workspace" | cmux pane |
| Finding or killing a Claude session in a sibling workspace | cmux (read-screen + send) |

Rule of thumb: if the task is <30s and single-round, skip cmux. Otherwise consider it.

## Quick orientation

```bash
cmux identify         # your workspace/surface/pane refs + socket path
cmux tree             # full topology: windows → workspaces → panes → surfaces
cmux list-workspaces  # workspace refs + names
cmux list-pane-surfaces  # all surfaces with their parent panes
cmux ping             # liveness check (returns PONG)
```

Refs are short: `window:1`, `workspace:N`, `pane:N`, `surface:N`. Use these, not UUIDs.

## Primitives reference

| Action | Command |
|---|---|
| New workspace | `cmux new-workspace --cwd <path> --name "<role>"` |
| New split in current workspace | `cmux new-split <left\|right\|up\|down>` |
| Send text (trailing `\n` = Enter) | `cmux send --workspace <ref> "<text>\n"` |
| Send named key | `cmux send-key --workspace <ref> <return\|ctrl+c\|escape\|tab>` |
| Read current screen | `cmux read-screen --workspace <ref> [--lines N] [--scrollback]` |
| Force refresh stale buffers | `cmux refresh-surfaces` |
| Rename (for sidebar clarity) | `cmux rename-workspace --workspace <ref> "<name>"` / `cmux rename-tab --surface <ref> "<name>"` |
| Close | `cmux close-workspace --workspace <ref>` / `cmux close-surface --surface <ref>` |
| Notify | `cmux notify --title "<t>" --body "<b>"` |

## Critical rules (non-negotiable)

1. **Mid-string `\n` doesn't break lines.** `send "a\nb\n"` sends `a\nb` followed by Enter — `a` and `b` become one line. For multi-line input, `send` each line then `send-key return` between them. Only the final `\n` works.

2. **`send-key` is for named keys only.** `return`, `ctrl+c`, `escape`, `tab`, `up`, `down`. Bare characters like `q` (to exit a pager) must use `send "q"`. `send-key q` silently does nothing.

3. **Cross-workspace = `--workspace`, never `--surface`.** `--surface` only works on surfaces inside the caller's own workspace; passing a sibling workspace's surface ref errors with `"Surface is not a terminal"`. For any other workspace use `--workspace workspace:N` — it auto-resolves to that workspace's focused surface.

4. **Poll discipline.** Before every `read-screen` during a polling loop, call `cmux refresh-surfaces`. Read **≥ 50 lines** (`--lines 60` is a safe default). Small line counts miss the spinner line and produce false "idle" signals.

5. **Never launch with `--dangerously-skip-permissions`** unless the user has explicitly authorized it for the session. Plain `claude` is safe and runs in auto mode by default.

6. **Always clean up.** After a subagent finishes: `/exit` → `sleep 2` → `close-workspace`. Orphaned Claude sessions burn tokens and clutter the sidebar.

## Subagent lifecycle

The core loop. Follow step-by-step; each step is cheap.

### 1. Spawn a named workspace

```bash
WS=$(cmux new-workspace --cwd "$(pwd)" --name "🤖 Claude worker: <role>" | awk '{print $2}')
# $WS = workspace:N
```

Always give it a name. Sidebar visibility is the whole point.

### 2. Launch Claude

```bash
cmux send --workspace "$WS" "claude\n"
```

Plain `claude`, no flags. Auto mode is on by default inside the subagent.

### 3. Handle trust prompt (first run in a new cwd)

```bash
sleep 3
cmux refresh-surfaces >/dev/null
screen=$(cmux read-screen --workspace "$WS" --lines 60)
if echo "$screen" | grep -qiE "do you trust|yes, i trust"; then
  # Ask the user to approve in the pane — don't auto-accept
  echo "Trust prompt in $WS — please approve it in the pane"
  # Wait for user approval, then proceed
fi
```

### 4. Wait for ready

```bash
for i in $(seq 1 15); do
  sleep 2
  cmux refresh-surfaces >/dev/null
  screen=$(cmux read-screen --workspace "$WS" --lines 60)
  echo "$screen" | grep -q "for shortcuts" && break
done
```

Ready = the bottom status line shows `? for shortcuts` and a bare `❯` input.

### 5. Send the prompt

Single line:

```bash
cmux send --workspace "$WS" "<your prompt>\n"
```

Multi-line:

```bash
cmux send --workspace "$WS" "line 1"
cmux send-key --workspace "$WS" return
cmux send --workspace "$WS" "line 2"
cmux send-key --workspace "$WS" return
cmux send-key --workspace "$WS" return  # final Enter to submit
```

### 6. Poll for completion

```bash
for i in $(seq 1 60); do
  sleep 4
  cmux refresh-surfaces >/dev/null
  screen=$(cmux read-screen --workspace "$WS" --lines 60)
  # Working markers: spinner line, tokens counter, "esc to interrupt"
  if echo "$screen" | grep -qE "esc to interrupt|↓ [0-9]+ tokens|ctrl\+o to expand"; then
    continue
  fi
  break  # markers gone → idle/done
done
```

If the poll hits its cap without finding idle, either bump the cap or read-screen manually to inspect.

### 7. Collect the answer

```bash
result=$(cmux read-screen --workspace "$WS" --scrollback --lines 200)
```

Extract the final assistant turn from `$result`. The `❯` input box bounds the response from below.

### 8. Notify + teardown

```bash
cmux notify --title "Worker done" --body "<one-line summary>"
cmux send --workspace "$WS" "/exit\n"
sleep 2
cmux close-workspace --workspace "$WS"
```

## Parallel workers pattern

Spawn N subagents, poll round-robin, collect all, teardown. **Cap at 4 concurrent Claude subagents** unless the user explicitly asks for more — each is real API cost.

```bash
# Spawn
declare -a WORKERS
for role in "scan-auth" "scan-db" "scan-api"; do
  ws=$(cmux new-workspace --cwd "$(pwd)" --name "🤖 $role" | awk '{print $2}')
  cmux send --workspace "$ws" "claude\n"
  WORKERS+=("$ws:$role")
done

# (wait for ready, send prompts — loop over WORKERS)

# Poll round-robin until all idle
# (check each $ws, track which are done)

# Collect
for entry in "${WORKERS[@]}"; do
  ws="${entry%%:*}"
  cmux read-screen --workspace "$ws" --scrollback --lines 200
done

# Teardown
for entry in "${WORKERS[@]}"; do
  ws="${entry%%:*}"
  cmux send --workspace "$ws" "/exit\n"
done
sleep 2
for entry in "${WORKERS[@]}"; do
  ws="${entry%%:*}"
  cmux close-workspace --workspace "$ws"
done
```

## Long-lived side processes

Dev server, log tail, watch-build, etc. These live in their own pane and you poll them on demand — not continuously.

```bash
# Sibling pane in the current workspace
SURF=$(cmux new-split right | awk '{print $2}')
cmux rename-tab --surface "$SURF" "dev-server"
cmux send --surface "$SURF" "npm run dev\n"

# Later, on demand (same workspace → --surface is fine here)
cmux read-screen --surface "$SURF" --lines 40
```

Don't poll in a tight loop. Read when the user asks, or when you have another reason to check (task wants to hit the server, build just finished, etc.).

## Pane reuse

Before spawning a new pane, look for an idle one (shell prompt only, no running process).

```bash
cmux list-pane-surfaces
for s in surface:1 surface:2 surface:3; do
  screen=$(cmux read-screen --surface "$s" --lines 5)
  # Idle heuristic: last non-empty line matches a shell prompt
  echo "$screen" | grep -qE '[➜\$❯#] *$' && echo "$s is idle"
done
```

Reuse saves GUI clutter. Only create new panes when none are idle.

## Notifications

Two channels, different audiences:

```bash
# In-app: sidebar badge + pane highlight. Use when cmux is foregrounded.
cmux notify --title "Build done" --body "tests 47/47 pass"

# macOS Notification Center: banner + sound. Use when user may be in another app.
osascript -e 'display notification "Needs your input" with title "Claude" sound name "Glass"'
```

Fire both when the subagent needs a human decision — you don't know which app the user is in.

## Finding and controlling sibling Claude sessions

Common ask: "there's a Claude session running in another workspace, kill it / check it / tell it X."

1. `cmux tree` — look for surfaces labeled `"Claude Code"` or `"✳ ..."` (Claude sessions name themselves by current task).
2. `cmux read-screen --workspace <ref> --lines 20` — confirm it's idle or see what it's doing.
3. To kill cleanly: `cmux send --workspace <ref> "/exit\n"` → `sleep 2`. If stuck: `cmux send-key --workspace <ref> ctrl+c` first, then `/exit`.
4. Don't `close-workspace` a sibling if it has other live panes the user cares about — close only the Claude surface if needed (`close-surface --surface <ref>`).

## Common mistakes

| Mistake | Fix |
|---|---|
| `send "line1\nline2\n"` for multi-line | `send "line1"` + `send-key return` + `send "line2"` + `send-key return` |
| `send-key q` to exit a pager | `send "q"` (bare chars go through send) |
| `send "C-c"` / `send "\x03"` for Ctrl+C | `send-key ctrl+c` |
| `--surface surface:N` for another workspace | `--workspace workspace:N` |
| `read-screen` returns empty → give up | `cmux refresh-surfaces` first, retry |
| `read-screen --lines 10` during poll | use `--lines 60+`, otherwise you miss the spinner |
| Launching with `--dangerously-skip-permissions` | plain `claude` (ask before enabling skip) |
| `/exit` as the only cleanup | `/exit` → `sleep 2` → `close-workspace` |
| Unnamed workspace | always `--name "🤖 <role>"` so the sidebar is legible |
| Leaving subagents alive after collect | teardown every time — they burn tokens |
| Spawning 10 parallel subagents "just in case" | cap at 4 unless the user explicitly authorizes more |

## Environment variables

| Var | Meaning |
|---|---|
| `CMUX_SOCKET_PATH` | Path to cmux socket. If set, you're running inside cmux. |
| `CMUX_WORKSPACE_ID` | UUID of your current workspace |
| `CMUX_SURFACE_ID` | UUID of your current surface |

If `CMUX_SOCKET_PATH` is unset, cmux isn't running — fall back to the built-in Agent tool and tell the user.
