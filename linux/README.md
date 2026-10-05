# linux/

Bootstrap for a Linux box — a k8s dev pod, a shared VM, anything where you
land in a bash shell with no root and want the same muscle memory as the
Mac.

## Why this sits outside `home/`

`.chezmoiroot` points chezmoi at `home/`, so nothing in this directory is
ever deployed by `chezmoi apply`. That is deliberate. The chezmoi tree is
macOS-shaped: `run_once_before_install-deps.sh.tmpl` installs Homebrew and
runs `brew bundle`, `run_once_after_macos-defaults.sh.tmpl` runs `defaults
write`. Running any of it on Linux is wrong, and chezmoi's `run_once`
scripts fire on a bare `chezmoi apply`.

So `bootstrap.sh` copies the handful of genuinely cross-platform files
itself and does the chezmoi name translation (`dot_` → `.`,
`executable_` → `+x`) inline. chezmoi is never installed on the box.

## Usage

```sh
git clone https://github.com/mynk93/dotfiles.git ~/.dotfiles
~/.dotfiles/linux/bootstrap.sh --t3
exec bash -l
```

`--git-name` and `--git-email` set the git identity. `--claude-code` installs the Claude
Code CLI (logging in stays a manual step); `--claudex` additionally installs
CLIProxyAPI and the claudex harness (see below); `--t3` installs the T3 Code
server and the Codex CLI and registers the supervised services (it needs a
node from nvm under `~/.config/nvm` first, see below). Flags `--skip-tools`,
`--skip-claude`, `--skip-configs`, `--skip-shell` narrow what runs; all
steps are idempotent, so re-running is the upgrade path.

## What it installs

| Path | From | Notes |
|---|---|---|
| `~/.local/bin/*` | GitHub Releases | eza, bat, fd, rg, fzf, zoxide, delta, glow, jq, gh, lazygit, moor |
| `~/.local/bin/claude` | `claude.ai/install.sh` | `--claude-code` only |
| `~/.claude/` | `home/dot_claude/` | CLAUDE.md, rules, skills, statusline script |
| `~/.claude/settings.json` | `linux/claude/settings.json` | Linux variant, see below |
| `~/.vimrc` | `home/dot_vimrc` | verbatim |
| `~/.config/bash/bashrc.linux` | `linux/bashrc.linux` | sourced from `~/.bashrc` |
| `~/.config/bash/local.bash` | generated | per-machine, never committed |
| `~/.gitconfig` | `linux/gitconfig` | no `[user]` block, see below |
| `~/.config/git/local` | generated | git identity, never committed |
| `~/.config/{bat,btop,glow,git,lazygit}/` | `home/dot_config/` | identical on both platforms |
| `~/.local/bin/claudex` | `home/dot_local/bin/` | `--claudex` only |
| `~/.config/cliproxyapi/` | `linux/cliproxyapi.yaml` | `--claudex` only, key generated locally |
| `~/.local/bin/{node,npm,npx,t3,codex}` | generated | `--t3` only, nvm PATH shims |
| `~/.config/nvm/.../lib/node_modules/{t3,@openai/codex}` | npm | `--t3` only |
| `~/.local/bin/*-run`, `s6-user-services-install` | `linux/bin/` | `--t3` / `--claudex`, supervised-service scripts |
| `~/.config/s6-user/` | `linux/s6-user/` | `--t3` / `--claudex`, s6 service definitions |

### The work checkout

`clone-work-repos.sh` clones the `prodigal-tech` repos into `~/dev/work`.
It is not part of `bootstrap.sh`, because it needs a GitHub credential the
bootstrap does not create — and without one all 24 clones fail at once.
So, once per box:

```sh
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github -C "<box-name>"
printf 'Host github.com\n    User git\n    IdentityFile ~/.ssh/id_ed25519_github\n    IdentitiesOnly yes\n' \
    >> ~/.ssh/config
cat ~/.ssh/id_ed25519_github.pub    # add this to github.com/settings/keys
~/.dotfiles/linux/clone-work-repos.sh
```

Generate the key on the box; never copy one between boxes. The clone is
also what creates `~/dev/work`, which matters because `t3-serve` serves
sessions from there.

### claudex on a remote box

`--claudex` installs CLIProxyAPI alongside the harness so the box serves its
own proxy on `127.0.0.1:8317`. The alternative — reverse-tunnelling the
Mac's proxy — was rejected because it only works while the Mac is awake,
which defeats the point of driving the box from a phone.

No credential is committed and none is copied off the Mac. The proxy config
is a template with an `__API_KEY__` placeholder; bootstrap generates a key
on the box, writes it to `~/.config/cliproxyapi/{key,config.yaml}` at mode
600, and never overwrites an existing pair — so re-running cannot invalidate
a proxy you have already logged in to. Upstream auth is a one-time device
code flow that needs no browser on the box:

```sh
~/.local/bin/cli-proxy-api -config ~/.config/cliproxyapi/config.yaml \
    -codex-device-login
```

The proxy runs as the `cliproxyapi` s6 service, so it comes back after a pod
restart without anybody logging in.

Note that `codex-review` still will not run here: it orchestrates reviewer
sessions in cmux panes, and cmux is macOS-native.

### Supervised services

There is no systemd on these boxes. PID 1 is `s6-svscan`, watching
`/var/run/s6/services`, so anything that has to outlive an ssh session is an
s6 service. The catch is that `/var/run` is tmpfs: every service directory is
erased on a pod restart, while `$HOME` survives.

So the durable copy lives in `~/.config/s6-user/<name>/{run,finish}` — the
same layout s6 itself expects — and `s6-user-services-install` copies it into
the scan directory. `bashrc.linux` calls that on every interactive login, so
the box heals on the first shell after a restart. For real boot-time recovery
see below.

The run scripts and definitions hardcode `/home/jovyan`, the user every
TrueFoundry ssh-server pod runs as. A box with a different user needs that
path changed in `linux/bin/*-run` and `linux/s6-user/*/run` before the
service layer is installed; `$HOME` is not available to a `run` file s6
executes with the container's environment.

`finish` is not decoration. s6-supervise restarts a dead service immediately,
so a service that fails at startup spins at full CPU without one; every
`finish` here sleeps 5 seconds.

| Service | Does |
|---|---|
| `t3-serve` | T3 Code server on 127.0.0.1:3773 |
| `cliproxyapi` | the local proxy claudex drives, on 127.0.0.1:8317 |
| `tfy-activity-observer` | samples the idle-shutdown judge once a minute |

Opting out is one flag file, `~/.config/s6-user/<name>.disabled`. A flagged
service is not registered, and if it is already registered it is stopped in
place — s6 cannot forget a service directory without a scan-dir prune, so
"stopped" is as far as this goes. Removing the flag and re-running the
installer starts it. Nothing ships flagged.

The installer never rewrites a service that is already registered. Rewriting
`run` under a live `s6-supervise` would not take effect until a restart
anyway, and a service somebody stopped by hand should stay stopped.

A definition may carry an executable `check`; if it exits non-zero the
service is skipped rather than registered. `t3-serve` checks for the `t3`
shim and `cliproxyapi` for the proxy binary and config, which is what lets
`--t3` and `--claudex` install the whole service layer without a box that ran
only one of them supervising a service that restarts every five seconds
because its binary is missing.

### T3 Code server

[T3 Code](https://github.com/pingdotgg/t3code) drives Claude Code and Codex
sessions from a browser or phone against this box's checkouts. `t3 service
install` writes a systemd unit, which is useless here, so s6 supervises
`t3 serve` instead.

`--t3` expects a node under `~/.config/nvm` and stops if there is none. On a
fresh box, once (the installer honours `XDG_CONFIG_HOME`, which
`bashrc.linux` sets, so it lands in `~/.config/nvm`):

```sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash
exec bash -l
nvm install --lts && nvm alias default lts/*
```

Two things about node need care. nvm lives in `~/.config/nvm`, not `~/.nvm`,
and nvm is a shell function — so `ssh box 'node -v'` finds nothing, and
neither does a supervised service. `nvm-shims-install` writes shims for
`node`, `npm`, `npx`, `t3` and `codex` into `~/.local/bin` that resolve the
newest installed version at call time, so a node upgrade needs no re-run.
Symlinks into the versioned directory would not survive one.

The shims prepend the resolved bin directory to `PATH` *and* exec an absolute
path. Both are needed: `npm`, `npx`, `t3` and `codex` all carry a
`#!/usr/bin/env node` shebang and spawn further `node` children. For the same
reason no shim may call `node` by name — with `~/.local/bin` first on PATH
that is a fork bomb.

`npm` will not run install scripts by default, and T3 needs `node-pty` built:

```sh
npm i -g --allow-scripts=msgpackr-extract,node-pty t3@latest @openai/codex
```

Without the flag `t3 --version` still works and `t3 serve` dies the moment it
opens a terminal.

State goes to `~/.t3/userdata` (`T3CODE_HOME`) — SQLite, logs, and the
signing keys. Projects are added out of band:

```sh
for d in ~/dev/work/*/; do t3 project add "$d" --title "$(basename "$d")"; done
```

How the server is exposed is a per-box decision, so it lives in
`~/.config/t3/serve.env` rather than in the run script. The default is
`--host 127.0.0.1`.

#### Reaching it — T3 Connect

`t3 connect link --headless` authorizes the environment "on next start" and
stores the grant under `~/.t3/userdata`. That is the whole trick: the s6
service stays a plain `t3 serve`, which reconciles the link at startup and
brings the managed tunnel up itself. The run script needs no change, and the
laptop is not in the path.

The tunnel is Cloudflare's — T3 downloads a `cloudflared` build it calls the
relay client. Both regional edges answer from this box
(`region{1,2}.v2.argotunnel.com:7844`), so nothing needs opening.

`t3 connect link` asks `Download and install version <x>?` for that relay
client, and the default answer is **no**. Answer `y`; declining leaves the
grant stored and the tunnel never comes up.

`t3 connect status --json` is read-only and safe to run before logging in.

Every start of `t3 serve` prints a fresh pairing token into
`~/.local/state/t3/serve.log` (mode 600). It only opens the loopback
listener and T3 Connect does not use it, but treat the log as a secret and
`t3 auth pairing revoke` anything that leaks.

#### Updating

The desktop app compares its own version against the server's and offers to
update it. That button cannot work here: remote updates go through
`t3 service install`, which writes a systemd unit. So the server is updated by
hand, and it should track whatever channel the client is on — a nightly
desktop against a stable server shows a banner it can never clear.

```sh
update-t3            # channel: $T3_CHANNEL, else whatever is installed
update-t3 nightly    # switch channel
```

From the laptop, the zsh `update-t3` in `functions.zsh` runs the same thing
over ssh, so an update does not need a shell on the box:

```sh
update-t3 <ssh-host>            # same channel rules, decided on the box
update-t3 <ssh-host> nightly
```

That is a function in `bashrc.linux` wrapping the two commands below, which
have to run together.

```sh
npm i -g --allow-scripts=msgpackr-extract,node-pty t3@nightly
s6-svc -r /var/run/s6/services/t3-serve
```
 T3 lazy-loads hashed chunks from the package directory,
so replacing it underneath a running server leaves the old process reaching
for files that no longer exist. The restart drops live connections; threads
are resumed from `state.sqlite`, so nothing is lost, but anything mid-turn
needs picking up again.

#### Context7 on the box

`~/.claude/rules/context7.md` and the `context7-mcp` skill come over with
the Claude config, but they only tell the agent to *use* Context7. The MCP
server itself is per-machine state -- Claude Code keeps it in `~/.claude.json`
and Codex in `~/.codex/config.toml` -- and neither is copied by the bootstrap
because both carry your API key. Once per box, with the key from
context7.com:

```sh
claude mcp add --scope user --transport http context7 https://mcp.context7.com/mcp \
    --header "CONTEXT7_API_KEY: <key>"
cat >> ~/.codex/config.toml <<'TOML'

[mcp_servers.context7]
http_headers = { "Authorization" = "Bearer <key>" }
url = "https://mcp.context7.com/mcp"
TOML
```

T3-spawned sessions pick both up: Claude loads user-scope servers alongside
the one T3 injects, and Codex reads its config on every start.

### Keeping the pod alive

TrueFoundry stops the pod when it judges it idle. Its own definition, from the
deployment form:

> The instance is considered active if there is at least one active SSH
> connection, or if a background job is running using tmux or screen, or if the
> pod has restarted.

The judge is `~/.truefoundry/tfy-ssh-activity-tracker`, an s6 service of its
own, serving `127.0.0.1:49155/v1/get-activity` and `/metrics`. It counts two
things: ESTABLISHED sockets whose local port is 8888 — this box's sshd port,
per `Port 8888` in `/etc/ssh/sshd_config`, so that half means inbound ssh and
nothing else — and processes that own a controlling terminal and sit in its
foreground group. The gauges are `tfy_ssh_server_active_sessions` and
`tfy_ssh_server_active_foreground_processes`.

The second rule is the one that bites: **an s6 service has no terminal, so the
judge cannot see it.** `t3-serve` and `cliproxyapi` are invisible to it. A box
doing real work through T3, with nobody sshed in, reads as idle.

Hence the `keep` session in `bashrc.linux` — `tmux new-session -d -s keep
'exec sleep infinity'`. A tmux-hosted background job is TrueFoundry's own
sanctioned definition of activity, so this is not a workaround so much as the
documented answer, and it is the smallest process that satisfies it. Verified:
`tfy_ssh_server_active_foreground_processes` moves by exactly one when the
session starts and back when it is killed.

"Stop After" on the deployment form is the other half and is set to 720
minutes. The sentinel only matters if that window ever expires.

`tfy-activity-observer` is the audit trail. Once a minute it appends the
tracker's own verdict next to a socket census taken the same second, to
`~/.local/state/tfy-activity/observer.log`, capped at 5000 lines. If the rule
above is ever wrong, it shows up there as a row where the counts and the
description do not line up.

### After a pod restart

`/var/run` is tmpfs, so a restart leaves the box with no services registered
and no `keep` session. Both come back on the first interactive login, which
means somebody has to ssh in once. Until "Boot-time recovery" below is wired
into the image, that is the runbook:

```sh
ssh <box>                       # the login hook does the work
tmux ls                         # expect: keep
s6-svstat /var/run/s6/services/t3-serve
s6-svstat /var/run/s6/services/cliproxyapi
s6-svstat /var/run/s6/services/tfy-activity-observer
t3 connect status --json        # expect linked true, relayClient not "missing"
curl -s 127.0.0.1:49155/metrics | grep tfy_ssh
cat ~/.local/state/s6-user-install.log
```

The T3 Connect link survives a restart — it lives in `~/.t3/userdata` — so
`t3 serve` re-establishes the tunnel on its own once the service is back.

### Boot-time recovery

`bashrc.linux` re-registers the services on the first interactive login
after a restart, which means a box nobody has logged into is a box with no
gateway and no T3 server. Closing that gap needs one file in the image, because
s6-overlay copies `/etc/services.d` into `/var/run/s6/services` at boot —
exactly how `activity-tracker-daemon` gets there.

In the TrueFoundry deployment's build script (it runs as `jovyan` with
`sudo`, the same way `sudo apt install` does):

```sh
sudo mkdir -p /etc/services.d/user-services
sudo tee /etc/services.d/user-services/run >/dev/null <<'EOF'
#!/usr/bin/with-contenv bash
# Register the user's own s6 services once $HOME is mounted, then park.
#
# PID 1 already runs as jovyan, so there is no uid to switch to -- and
# s6-setuidgid would fail here anyway, since setgroups needs a capability the
# container does not hold. Parking matters too: s6 restarts a service that
# exits, and finish scripts are killed after five seconds by default, so an
# exit here would re-run the installer every few seconds forever.
installer=/home/jovyan/.local/bin/s6-user-services-install
for _ in $(seq 1 60); do
    if [ -x "$installer" ]; then
        "$installer"
        exec sleep infinity
    fi
    sleep 2
done
echo "user-services: $installer never appeared" >&2
exec sleep infinity
EOF
sudo chmod +x /etc/services.d/user-services/run
```

### Why the git identity is split out

This repo is public, so `linux/gitconfig` carries the aliases, delta wiring,
and diff settings but no `[user]` block. `bootstrap.sh --git-name/--git-email`
writes the identity to `~/.config/git/local`, which `[include]` pulls in and
git never sees as committed. Same split `.ssh/config` uses with
`config.local`; a missing include is not an error.

The macOS `dot_gitconfig.tmpl` also differs in two places: `core.editor` is
`vim` rather than `zed --wait` (no GUI on a remote box, and vim already
blocks), and commit/tag signing is dropped because these boxes carry no GPG
key.

### Why settings.json is forked

The macOS `home/dot_claude/settings.json` wires a statusline that runs a
`#!/bin/zsh` script through `jq`, and enables three plugin marketplaces,
two of them private repos. On a bare Linux box there is no
zsh and no GitHub credential, so those produce a dead statusline and failing
marketplace fetches. The Linux variant drops all three keys. It used to set
`remoteControlAtStartup` and `crossSessionInbound` as well; with Remote
Control retired in favour of T3 Code those are gone too, since
`remoteControlAtStartup: true` would have every interactive `claude` on the
box start a gateway nothing talks to.

## What does not carry over

Dropped because it is macOS-only: `explorer` (`open`), `ip`
(`ipconfig getifaddr en0` — the alias is kept, with a Linux body), every
`zed` alias, `EDITOR='zed --wait'`, Homebrew shellenv.

Dropped because it is zsh-only: antidote plugins, `zstyle` menu
completion, the `mynk.zsh` prompt, the `add-zsh-hook` project-local
`.zshrc.local` loader. Bash gets the nearest readline equivalents —
prefix history search on Up/Down, case-insensitive completion — which are
close but not the same thing.

Dropped for missing dependencies: `prdiff` (`gh` is installed now, but it
also needs `hunk`, which comes from npm rather than the Brewfile), the `y`
yazi wrapper, `lzd` / `dbx`.
