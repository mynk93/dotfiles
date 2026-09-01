#!/usr/bin/env bash
# linux/bootstrap.sh — provision a Linux box with the shell + Claude config.
#
# chezmoi is deliberately not used here. Its source root (home/) and its
# run_once scripts are macOS-shaped — they install Homebrew and run
# `defaults write` — so applying them on Linux is wrong. This script copies
# the handful of cross-platform files directly and translates the chezmoi
# name prefixes (dot_ -> ., executable_ -> +x) itself.
#
# Everything lands under $HOME, which on a k8s dev pod is usually the only
# persistent, writable path. No root required.
#
# Usage:
#   git clone https://github.com/mynk93/dotfiles.git ~/.dotfiles
#   ~/.dotfiles/linux/bootstrap.sh --rc-prefix linux
#
# Flags:
#   --rc-prefix NAME   name this box in claude.ai/code session lists
#   --skip-tools       don't download CLI binaries
#   --skip-claude      don't touch ~/.claude
#   --skip-shell       don't touch ~/.bashrc

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BEGIN_MARK='# >>> dotfiles linux >>>'
END_MARK='# <<< dotfiles linux <<<'

RC_PREFIX=""
DO_TOOLS=1
DO_CLAUDE=1
DO_SHELL=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --rc-prefix)   RC_PREFIX="${2:?--rc-prefix needs a value}"; shift 2 ;;
        --skip-tools)  DO_TOOLS=0;  shift ;;
        --skip-claude) DO_CLAUDE=0; shift ;;
        --skip-shell)  DO_SHELL=0;  shift ;;
        -h|--help)     sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "bootstrap: unknown flag $1" >&2; exit 1 ;;
    esac
done

# ── 1. CLI binaries ────────────────────────────────────────
if [[ "$DO_TOOLS" == 1 ]]; then
    echo "==> Installing CLI tools"
    "$REPO/linux/install-tools.sh"
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

# ── 3. Shell ───────────────────────────────────────────────
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

echo "==> Done. Open a new shell, or: source ~/.bashrc"
