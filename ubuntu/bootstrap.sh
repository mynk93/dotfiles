#!/usr/bin/env bash
# ubuntu/bootstrap.sh — provision an Ubuntu machine you administer.
#
# The counterpart to linux/bootstrap.sh, which targets a rootless k8s pod.
# This one assumes what that one cannot: sudo, apt, and systemd. So system
# packages come from apt, services are left to systemd (`t3 up` installs its
# own unit), and nothing here knows about s6, nvm shims, or idle shutdown.
#
# The cross-platform steps (CLI binaries, Claude config, tool configs, git
# config) are not repeated here. linux/bootstrap.sh already does them and
# nothing about them is pod-specific, so this script runs it with
# --skip-shell and then installs its own shell config and git signing.
#
# Usage:
#   sudo apt-get install -y git
#   git clone https://github.com/mynk93/dotfiles.git ~/.dotfiles
#   ~/.dotfiles/ubuntu/bootstrap.sh \
#       --git-name "Your Name" --git-email you@example.com
#
# Flags:
#   --git-name NAME    git author name  -> ~/.config/git/local (never committed)
#   --git-email EMAIL  git author email -> ~/.config/git/local (never committed)
#   --gpg-key KEYID    sign commits and tags with this key -> ~/.config/git/local
#   --skip-apt         don't install system packages (no sudo needed then)
#   --skip-tools       don't download CLI binaries
#   --skip-claude      don't touch ~/.claude
#   --skip-configs     don't touch ~/.gitconfig or ~/.config/{bat,btop,glow,git,lazygit}
#   --skip-shell       don't touch ~/.bashrc

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# What the configs in this repo assume is present. Everything else arrives as
# a static binary from linux/install-tools.sh, so it tracks upstream releases
# rather than the distribution's.
APT_PACKAGES=(git curl vim gnupg btop python3)

GPG_KEY=""
DO_APT=1
DO_SHELL=1
DO_CONFIGS=1
PASSTHROUGH=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --git-name|--git-email)
            PASSTHROUGH+=("$1" "${2:?$1 needs a value}"); shift 2 ;;
        --gpg-key)      GPG_KEY="${2:?--gpg-key needs a value}"; shift 2 ;;
        --skip-apt)     DO_APT=0;   shift ;;
        --skip-shell)   DO_SHELL=0; shift ;;
        --skip-configs) DO_CONFIGS=0; PASSTHROUGH+=("$1"); shift ;;
        --skip-tools|--skip-claude)
            PASSTHROUGH+=("$1"); shift ;;
        -h|--help)      sed -n '2,29p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "bootstrap: unknown flag $1" >&2; exit 1 ;;
    esac
done

# ── 1. System packages ─────────────────────────────────────
if [[ "$DO_APT" == 1 ]]; then
    echo "==> Installing apt packages: ${APT_PACKAGES[*]}"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${APT_PACKAGES[@]}"
    echo
fi

# ── 2. Cross-platform steps ────────────────────────────────
# Tools, Claude config, tool configs and ~/.gitconfig. The shell step is
# skipped because it installs the pod variant.
#
# linux/bootstrap.sh rewrites ~/.config/git/local whenever it is handed an
# identity, which would drop a signing key set on an earlier run. Carry the
# existing key over unless this run names one.
if [[ -z "$GPG_KEY" ]]; then
    GPG_KEY="$(git config --file "$HOME/.config/git/local" user.signingkey 2>/dev/null || true)"
fi
"$REPO/linux/bootstrap.sh" --skip-shell "${PASSTHROUGH[@]}"

# ── 3. Commit signing ──────────────────────────────────────
# linux/gitconfig carries no signing settings because a pod holds no key. A
# machine you administer can, so the key goes in ~/.config/git/local next to
# the identity: per-machine, and never committed. `git config --file` sets
# each value in place, so re-running neither duplicates nor drops them.
if [[ -n "$GPG_KEY" && "$DO_CONFIGS" == 1 ]]; then
    echo "==> Enabling commit and tag signing"
    if ! gpg --list-secret-keys "$GPG_KEY" >/dev/null 2>&1; then
        echo "    ERROR: no secret key $GPG_KEY in this keyring (see ubuntu/README.md)" >&2
        exit 1
    fi
    local_cfg="$HOME/.config/git/local"
    mkdir -p "$(dirname "$local_cfg")"
    git config --file "$local_cfg" user.signingkey "$GPG_KEY"
    git config --file "$local_cfg" commit.gpgsign true
    git config --file "$local_cfg" tag.gpgsign true
    chmod 600 "$local_cfg"
    echo "    signing with $GPG_KEY, written to ~/.config/git/local"
    echo
fi

# ── 4. Shell ───────────────────────────────────────────────
if [[ "$DO_SHELL" == 1 ]]; then
    echo "==> Installing shell config"
    mkdir -p ~/.config/bash
    cp "$REPO/linux/bashrc.common"  ~/.config/bash/bashrc.common
    cp "$REPO/ubuntu/bashrc.ubuntu" ~/.config/bash/bashrc.ubuntu

    # One line in ~/.bashrc, added once. Ubuntu's stock ~/.bashrc stays as it
    # is; ours is sourced after it and so wins where the two overlap.
    hook='[ -f ~/.config/bash/bashrc.ubuntu ] && . ~/.config/bash/bashrc.ubuntu'
    if ! grep -qxF "$hook" ~/.bashrc 2>/dev/null; then
        printf '\n# dotfiles ubuntu\n%s\n' "$hook" >> ~/.bashrc
    fi
    echo "    ~/.config/bash/bashrc.{common,ubuntu} installed and sourced from ~/.bashrc"

    # Per-machine settings live outside version control.
    [[ -f ~/.config/bash/local.bash ]] || touch ~/.config/bash/local.bash
    echo
fi

echo "==> Ubuntu bootstrap done. Open a new shell, or: source ~/.bashrc"
