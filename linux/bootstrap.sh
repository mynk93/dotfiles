#!/usr/bin/env bash
# linux/bootstrap.sh — provision a Linux box with the shell, git, and Claude config.
#
# chezmoi is deliberately not used here. Its source root (home/) and its
# run_once scripts are macOS-shaped — they install Homebrew and run
# `defaults write` — so applying them on Linux is wrong. This script copies
# the handful of cross-platform files directly and translates the chezmoi
# name prefixes (dot_ -> ., executable_ -> +x, private_ -> 700) itself.
#
# Everything lands under $HOME, which on a k8s dev pod is usually the only
# persistent, writable path. No root required.
#
# Usage:
#   git clone https://github.com/mynk93/dotfiles.git ~/.dotfiles
#   ~/.dotfiles/linux/bootstrap.sh --rc-prefix linux \
#       --git-name "Your Name" --git-email you@example.com
#
# Flags:
#   --rc-prefix NAME   name this box in claude.ai/code session lists
#   --git-name NAME    git author name  -> ~/.config/git/local (never committed)
#   --git-email EMAIL  git author email -> ~/.config/git/local (never committed)
#   --skip-tools       don't download CLI binaries
#   --skip-claude      don't touch ~/.claude
#   --skip-configs     don't touch ~/.gitconfig or ~/.config/{bat,btop,glow,git,lazygit}
#   --skip-shell       don't touch ~/.bashrc
#   --claudex          also install CLIProxyAPI + the claudex harness (opt-in;
#                      needs a one-time device-code login, see the notes it prints)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BEGIN_MARK='# >>> dotfiles linux >>>'
END_MARK='# <<< dotfiles linux <<<'

RC_PREFIX=""
GIT_NAME=""
GIT_EMAIL=""
DO_TOOLS=1
DO_CLAUDE=1
DO_CONFIGS=1
DO_SHELL=1
DO_CLAUDEX=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rc-prefix)    RC_PREFIX="${2:?--rc-prefix needs a value}"; shift 2 ;;
        --git-name)     GIT_NAME="${2:?--git-name needs a value}";   shift 2 ;;
        --git-email)    GIT_EMAIL="${2:?--git-email needs a value}"; shift 2 ;;
        --skip-tools)   DO_TOOLS=0;   shift ;;
        --skip-claude)  DO_CLAUDE=0;  shift ;;
        --skip-configs) DO_CONFIGS=0; shift ;;
        --skip-shell)   DO_SHELL=0;   shift ;;
        --claudex)      DO_CLAUDEX=1; shift ;;
        -h|--help)      sed -n '2,27p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "bootstrap: unknown flag $1" >&2; exit 1 ;;
    esac
done

# ── 1. CLI binaries ────────────────────────────────────────
if [[ "$DO_TOOLS" == 1 ]]; then
    echo "==> Installing CLI tools"
    if [[ "$DO_CLAUDEX" == 1 ]]; then
        "$REPO/linux/install-tools.sh" --with-claudex
    else
        "$REPO/linux/install-tools.sh"
    fi
    echo
fi

# ── 2. Claude config ───────────────────────────────────────
# Mirrors home/dot_claude, except settings.json: the macOS file wires a
# zsh+jq statusline and three plugin marketplaces (two of them private
# repos), none of which resolve on a bare Linux box. linux/claude/
# holds the Linux variant instead.
if [[ "$DO_CLAUDE" == 1 ]]; then
    echo "==> Installing Claude config into ~/.claude"
    src="$REPO/home/dot_claude"
    mkdir -p ~/.claude/rules ~/.claude/scripts ~/.claude/skills
    cp "$src/CLAUDE.md" ~/.claude/CLAUDE.md
    cp -r "$src/rules/." ~/.claude/rules/
    cp "$src/scripts/executable_context-bar.sh" ~/.claude/scripts/context-bar.sh
    chmod 755 ~/.claude/scripts/context-bar.sh
    cp -r "$src/skills/." ~/.claude/skills/

    # Preserve whatever the box came with, once.
    if [[ -f ~/.claude/settings.json && ! -f ~/.claude/settings.json.bak ]]; then
        cp ~/.claude/settings.json ~/.claude/settings.json.bak
        echo "    backed up existing settings.json -> settings.json.bak"
    fi
    cp "$REPO/linux/claude/settings.json" ~/.claude/settings.json
    python3 -c 'import json,sys;json.load(open(sys.argv[1]))' ~/.claude/settings.json
    echo "    settings.json installed and parsed clean"

    cp "$REPO/home/dot_vimrc" ~/.vimrc
    chmod 644 ~/.vimrc
    echo "    ~/.vimrc installed"
    echo
fi

# ── 3. Tool configs + git ──────────────────────────────────
# These tools are configured identically on both platforms, so the configs
# come straight from home/dot_config with no Linux variant.
if [[ "$DO_CONFIGS" == 1 ]]; then
    echo "==> Installing tool configs"
    cfg="$REPO/home/dot_config"
    mkdir -p ~/.config/bat ~/.config/btop ~/.config/git ~/.config/lazygit
    cp "$cfg/bat/config"          ~/.config/bat/config
    cp "$cfg/btop/btop.conf"      ~/.config/btop/btop.conf
    cp "$cfg/git/ignore"          ~/.config/git/ignore
    cp "$cfg/lazygit/config.yml"  ~/.config/lazygit/config.yml
    # chezmoi's private_ prefix means 700 on the deployed directory.
    mkdir -p ~/.config/glow && chmod 700 ~/.config/glow
    cp "$cfg/private_glow/glow.yml" ~/.config/glow/glow.yml
    echo "    bat, btop, glow, git ignore, lazygit"

    cp "$REPO/linux/gitconfig" ~/.gitconfig
    chmod 644 ~/.gitconfig
    echo "    ~/.gitconfig installed (identity kept out of it — see below)"

    # Identity lives outside version control: this repo is public.
    if [[ -n "$GIT_NAME" || -n "$GIT_EMAIL" ]]; then
        {
            echo "# Written by linux/bootstrap.sh. Never commit this file."
            echo "[user]"
            [[ -n "$GIT_NAME"  ]] && printf '\tname = %s\n'  "$GIT_NAME"
            [[ -n "$GIT_EMAIL" ]] && printf '\temail = %s\n' "$GIT_EMAIL"
        } > ~/.config/git/local
        chmod 600 ~/.config/git/local
        echo "    identity written to ~/.config/git/local"
    elif [[ ! -f ~/.config/git/local ]]; then
        echo "    WARNING: no git identity set. Commits will fail until you run:"
        echo "             $0 --git-name 'Your Name' --git-email you@example.com"
    fi
    echo
fi

# ── 4. Shell ───────────────────────────────────────────────
if [[ "$DO_SHELL" == 1 ]]; then
    echo "==> Installing shell config"
    mkdir -p ~/.config/bash
    cp "$REPO/linux/bashrc.linux" ~/.config/bash/bashrc.linux

    # Replace any previously managed block rather than appending a second.
    if [[ -f ~/.bashrc ]] && grep -qF "$BEGIN_MARK" ~/.bashrc; then
        python3 - "$HOME/.bashrc" "$BEGIN_MARK" "$END_MARK" <<'PY'
import sys
path, begin, end = sys.argv[1:4]
lines = open(path).read().splitlines(keepends=True)
out, skip = [], False
for line in lines:
    if line.strip() == begin:
        skip = True
    if not skip:
        out.append(line)
    if line.strip() == end:
        skip = False
open(path, "w").writelines(out)
PY
        echo "    removed previous managed block"
    fi

    {
        printf '\n%s\n' "$BEGIN_MARK"
        printf '[ -f ~/.config/bash/bashrc.linux ] && . ~/.config/bash/bashrc.linux\n'
        printf '%s\n' "$END_MARK"
    } >> ~/.bashrc
    echo "    ~/.config/bash/bashrc.linux installed and sourced from ~/.bashrc"

    # Per-machine settings live outside version control.
    if [[ -n "$RC_PREFIX" ]]; then
        touch ~/.config/bash/local.bash
        if grep -q '^export CLAUDE_RC_PREFIX=' ~/.config/bash/local.bash 2>/dev/null; then
            sed -i "s|^export CLAUDE_RC_PREFIX=.*|export CLAUDE_RC_PREFIX='$RC_PREFIX'|" \
                ~/.config/bash/local.bash
        else
            printf "export CLAUDE_RC_PREFIX='%s'\n" "$RC_PREFIX" >> ~/.config/bash/local.bash
        fi
        echo "    CLAUDE_RC_PREFIX=$RC_PREFIX written to ~/.config/bash/local.bash"
    fi
    echo
fi

# ── 5. claudex + CLIProxyAPI ───────────────────────────────
# The proxy holds upstream OAuth credentials, so nothing here is committed:
# the config comes from a template with a placeholder, and the API key is
# generated on this box. The key is never regenerated once it exists, so a
# re-run cannot invalidate a proxy you already logged in to; the config
# itself is rewritten every run so template changes actually land.
if [[ "$DO_CLAUDEX" == 1 ]]; then
    echo "==> Installing claudex + CLIProxyAPI"
    install -m 755 "$REPO/home/dot_local/bin/executable_claudex" ~/.local/bin/claudex
    echo "    ~/.local/bin/claudex installed"

    mkdir -p ~/.config/cliproxyapi && chmod 700 ~/.config/cliproxyapi
    if [[ -f ~/.config/cliproxyapi/key ]]; then
        echo "    reusing existing proxy key"
        api_key="$(cat ~/.config/cliproxyapi/key)"
    else
        api_key="sk-cliproxy-$(head -c 20 /dev/urandom | od -An -tx1 | tr -d ' \n')"
        printf '%s' "$api_key" > ~/.config/cliproxyapi/key
        chmod 600 ~/.config/cliproxyapi/key
        echo "    generated a proxy key -> ~/.config/cliproxyapi/key (mode 600)"
    fi

    # Always regenerate from the template so alias/tier changes propagate;
    # the key is substituted back in, so an existing device login survives.
    # Hand edits to config.yaml do not — put them in the template instead.
    sed "s|__API_KEY__|$api_key|" "$REPO/linux/cliproxyapi.yaml" \
        > ~/.config/cliproxyapi/config.yaml
    chmod 600 ~/.config/cliproxyapi/config.yaml
    echo "    config.yaml regenerated (loopback only, management API disabled)"

    if [[ -d ~/.cli-proxy-api ]] && compgen -G ~/.cli-proxy-api/'codex-*.json' >/dev/null; then
        echo "    upstream Codex credential already present"
    else
        echo
        echo "    ONE-TIME LOGIN REQUIRED — no upstream credential yet. Run:"
        echo "      ~/.local/bin/cli-proxy-api -config ~/.config/cliproxyapi/config.yaml \\"
        echo "        -codex-device-login"
        echo "    It prints a code to enter in a browser on any device; no browser"
        echo "    is needed on this box. Then open a new shell to start the proxy."
    fi
    echo
fi

echo "==> Done. Open a new shell, or: source ~/.bashrc"
