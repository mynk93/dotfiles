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
~/.dotfiles/linux/bootstrap.sh --rc-prefix <box-name>
exec bash -l
```

`--rc-prefix` names the box in claude.ai/code session lists. `--git-name`
and `--git-email` set the git identity. `--claudex` additionally installs
CLIProxyAPI and the claudex harness (see below). Flags `--skip-tools`,
`--skip-claude`, `--skip-configs`, `--skip-shell` narrow what runs; all
steps are idempotent, so re-running is the upgrade path.

## What it installs

| Path | From | Notes |
|---|---|---|
| `~/.local/bin/*` | GitHub Releases | eza, bat, fd, rg, fzf, zoxide, delta, glow, jq, gh, lazygit, moor |
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

The proxy then runs under a `proxy` tmux session, started by the same
interactive-shell hook that keeps Remote Control alive.

Note that `codex-review` still will not run here: it orchestrates reviewer
sessions in cmux panes, and cmux is macOS-native.

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
marketplace fetches. The Linux variant drops all three keys and keeps
`remoteControlAtStartup` / `crossSessionInbound`, which the Mac file does
not set.

## What does not carry over

Dropped because it is macOS-only: `explorer` (`open`), `ip`
(`ipconfig getifaddr en0`), every `zed` alias, `EDITOR='zed --wait'`,
Homebrew shellenv, `PAGER='moor'`.

Dropped because it is zsh-only: antidote plugins, `zstyle` menu
completion, the `mynk.zsh` prompt, the `add-zsh-hook` project-local
`.zshrc.local` loader. Bash gets the nearest readline equivalents —
prefix history search on Up/Down, case-insensitive completion — which are
close but not the same thing.

Dropped for missing dependencies: `prdiff` (`gh` is installed now, but it
also needs `hunk`, which comes from npm rather than the Brewfile), the `y`
yazi wrapper, `lzd` / `dbx`.
