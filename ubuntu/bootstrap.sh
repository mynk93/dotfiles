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
# zsh is the login shell here, as on the Mac, and it reads the same config:
# home/dot_zshenv and home/dot_config/zsh, whose few macOS-only lines are
# guarded on $OSTYPE. bash keeps a config too, because scripts and agents
# still start it.
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
#   --skip-shell       don't touch ~/.bashrc, ~/.zshenv or ~/.config/zsh
#   --skip-chsh        install the zsh config but leave the login shell alone

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# What the configs in this repo assume is present. Everything else arrives as
# a static binary from linux/install-tools.sh, so it tracks upstream releases
# rather than the distribution's.
APT_PACKAGES=(
    git curl vim gnupg btop python3
    zsh            # login shell; config comes from home/dot_config/zsh
    chafa          # image previews in yazi
    fontconfig     # fc-cache, for the Nerd Font below
    xz-utils       # the Nerd Font release is a .tar.xz
    podman         # rootless containers; see "Containers" in README.md
    uidmap         # newuidmap/newgidmap, without which rootless podman fails
    passt          # pasta, podman's default rootless network
)

# Global Python CLIs, mirroring home/.chezmoiscripts/run_once_after_uv-tools.
UV_TOOLS=(truefoundry)   # TrueFoundry CLI (provides `tfy`)

# The font the mynk.zsh prompt's glyphs come from; the Brewfile's
# font-fira-code-nerd-font cask. Only terminals running on this machine use
# it. A terminal you connect from renders with its own fonts.
NERD_FONT=FiraCode

GPG_KEY=""
DO_APT=1
DO_SHELL=1
DO_CONFIGS=1
DO_TOOLS=1
DO_CHSH=1
PASSTHROUGH=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --git-name|--git-email)
            PASSTHROUGH+=("$1" "${2:?$1 needs a value}"); shift 2 ;;
        --gpg-key)      GPG_KEY="${2:?--gpg-key needs a value}"; shift 2 ;;
        --skip-apt)     DO_APT=0;   shift ;;
        --skip-shell)   DO_SHELL=0; shift ;;
        --skip-configs) DO_CONFIGS=0; PASSTHROUGH+=("$1"); shift ;;
        --skip-tools)   DO_TOOLS=0;   PASSTHROUGH+=("$1"); shift ;;
        --skip-chsh)    DO_CHSH=0;    shift ;;
        --skip-claude)  PASSTHROUGH+=("$1"); shift ;;
        -h|--help)      sed -n '2,35p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "bootstrap: unknown flag $1" >&2; exit 1 ;;
    esac
done

if [[ -n "$GPG_KEY" && "$DO_CONFIGS" == 0 ]]; then
    echo "bootstrap: --gpg-key writes git config, so it cannot be combined with --skip-configs" >&2
    exit 1
fi

# ── 1. System packages ─────────────────────────────────────
if [[ "$DO_APT" == 1 ]]; then
    echo "==> Installing apt packages: ${APT_PACKAGES[*]}"
    sudo apt-get update -qq
    # Errors still reach stderr; the per-package progress does not.
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        -o Dpkg::Use-Pty=0 "${APT_PACKAGES[@]}" >/dev/null
    # `podman compose` hands off to docker-compose. A separate install because
    # this package recommends docker.io, and with recommends on, apt would
    # bring the Docker daemon along.
    echo "==> Installing docker-compose-v2 without recommends"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        -o Dpkg::Use-Pty=0 --no-install-recommends docker-compose-v2 >/dev/null
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
echo "==> Running the portable steps (linux/bootstrap.sh --skip-shell)"
"$REPO/linux/bootstrap.sh" --skip-shell "${PASSTHROUGH[@]}"
echo

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

# ── 4. uv tools, font, yazi and Podman ─────────────────────
# The macOS run_once scripts that carry over, plus the Podman setup apt
# cannot do.
if [[ "$DO_TOOLS" == 1 ]]; then
    export PATH="$HOME/.local/bin:$PATH"
    if command -v uv >/dev/null 2>&1; then
        echo "==> Installing uv tools: ${UV_TOOLS[*]}"
        for tool in "${UV_TOOLS[@]}"; do
            # Idempotent: a no-op when the tool is already installed.
            uv tool install --quiet "$tool"
        done
    else
        echo "    uv not found; skipping ${UV_TOOLS[*]}"
    fi

    echo "==> Installing $NERD_FONT Nerd Font"
    font_dir="$HOME/.local/share/fonts/${NERD_FONT}NerdFont"
    mkdir -p "$font_dir"
    curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${NERD_FONT}.tar.xz" \
        | tar -xJ -C "$font_dir"
    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$font_dir"
    fi
    echo "    $(find "$font_dir" -name '*.ttf' | wc -l) font files in ${font_dir/#$HOME/\~}"
    echo
fi

if [[ "$DO_CONFIGS" == 1 ]]; then
    echo "==> Installing Podman config"
    # A drop-in rather than containers.conf itself, so a re-run leaves any
    # per-user settings made there alone.
    mkdir -p ~/.config/containers/containers.conf.d
    cp "$REPO/home/dot_config/containers/containers.conf.d/compose.conf" \
        ~/.config/containers/containers.conf.d/compose.conf
    # The package installs only the Docker CLI plugin path; podman compose and
    # bare `docker-compose` calls look on PATH.
    compose_plugin=/usr/libexec/docker/cli-plugins/docker-compose
    if [[ -x "$compose_plugin" ]]; then
        mkdir -p ~/.local/bin
        ln -sfn "$compose_plugin" ~/.local/bin/docker-compose
        "$HOME/.local/bin/docker-compose" version
    fi
    # Socket-activated: systemd holds the socket and starts the API service on
    # the first connection; the service exits again after 5 idle seconds.
    if command -v podman >/dev/null 2>&1; then
        systemctl --user enable --now podman.socket
        echo "    compose.conf installed, podman.socket enabled"
    else
        echo "    compose.conf installed; podman not found, socket not enabled (run without --skip-apt)"
    fi
    echo

    echo "==> Installing yazi config"
    mkdir -p ~/.config/yazi
    cp "$REPO/home/dot_config/yazi/yazi.toml"    ~/.config/yazi/yazi.toml
    cp "$REPO/home/dot_config/yazi/package.toml" ~/.config/yazi/package.toml
    if command -v ya >/dev/null 2>&1; then
        ya pkg install || echo "    WARNING: ya pkg install failed; run it by hand to see why"
    else
        echo "    ya not found; plugins in package.toml not installed"
    fi
    echo
fi

# ── 5. Shell ───────────────────────────────────────────────
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

    # zsh reads the macOS config as is. chezmoi is not installed here, so the
    # name translation (dot_ -> .) is done by hand, as linux/bootstrap.sh does
    # for the Claude config.
    zsrc="$REPO/home/dot_config/zsh"
    mkdir -p ~/.config/zsh/themes
    cp "$REPO/home/dot_zshenv"       ~/.zshenv
    cp "$zsrc/dot_zshrc"             ~/.config/zsh/.zshrc
    cp "$zsrc/dot_zsh_plugins.txt"   ~/.config/zsh/.zsh_plugins.txt
    cp "$zsrc/aliases.zsh"           ~/.config/zsh/aliases.zsh
    cp "$zsrc/functions.zsh"         ~/.config/zsh/functions.zsh
    cp "$zsrc/themes/mynk.zsh"       ~/.config/zsh/themes/mynk.zsh
    [[ -f ~/.config/zsh/local.zsh ]] || touch ~/.config/zsh/local.zsh

    # antidote, where .zshrc looks for it when Homebrew is absent.
    if [[ -d ~/.config/zsh/.antidote/.git ]]; then
        git -C ~/.config/zsh/.antidote pull --quiet --ff-only
    else
        git clone --quiet --depth=1 https://github.com/mattmc3/antidote.git ~/.config/zsh/.antidote
    fi
    echo "    ~/.zshenv, ~/.config/zsh and antidote installed"

    # First start clones the plugins and builds the completion cache. Doing it
    # here keeps that wait, and any error, out of the first real login.
    if command -v zsh >/dev/null 2>&1; then
        zsh -ic 'exit' </dev/null >/dev/null 2>&1 || echo "    WARNING: zsh -ic exited non-zero; run it by hand to see why"
        echo "    zsh plugins fetched"
    fi

    if [[ "$DO_CHSH" == 1 ]]; then
        zsh_path="$(command -v zsh || true)"
        current="$(getent passwd "$USER" | cut -d: -f7)"
        if [[ -z "$zsh_path" ]]; then
            echo "    zsh not found; login shell left as $current (run without --skip-apt)"
        elif [[ "$current" != "$zsh_path" ]]; then
            sudo chsh -s "$zsh_path" "$USER"
            echo "    login shell changed from $current to $zsh_path (takes effect at next login)"
        else
            echo "    login shell is already $zsh_path"
        fi
    fi
    echo
fi

echo "==> Ubuntu bootstrap done. Log in again, or: exec zsh -l"
