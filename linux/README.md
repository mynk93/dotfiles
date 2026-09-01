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

`--rc-prefix` names the box in claude.ai/code session lists. Flags
`--skip-tools`, `--skip-claude`, `--skip-shell` narrow what runs; all
steps are idempotent, so re-running is the upgrade path.

## What it installs

| Path | From | Notes |
|---|---|---|
| `~/.local/bin/*` | GitHub Releases | eza, bat, fd, rg, fzf, zoxide, delta, glow, jq |
| `~/.claude/` | `home/dot_claude/` | CLAUDE.md, rules, skills, statusline script |
| `~/.claude/settings.json` | `linux/claude/settings.json` | Linux variant, see below |
| `~/.vimrc` | `home/dot_vimrc` | verbatim |
| `~/.config/bash/bashrc.linux` | `linux/bashrc.linux` | sourced from `~/.bashrc` |
| `~/.config/bash/local.bash` | generated | per-machine, never committed |

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

Dropped for missing dependencies: `prdiff` (needs `gh` plus `hunk`, and
`hunk` comes from npm rather than the Brewfile), the `y` yazi wrapper,
`lzh` / `lzd` / `dbx`.

`delta` is installed but not wired — that lives in `~/.gitconfig`, which
this script does not manage because the chezmoi source is a template
needing name/email/GPG prompts.
