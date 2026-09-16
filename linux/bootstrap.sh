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
#   ~/.dotfiles/linux/bootstrap.sh --t3 \
#       --git-name "Your Name" --git-email you@example.com
#
# Flags:
#   --git-name NAME    git author name  -> ~/.config/git/local (never committed)
#   --git-email EMAIL  git author email -> ~/.config/git/local (never committed)
#   --skip-tools       don't download CLI binaries
#   --skip-claude      don't touch ~/.claude
#   --skip-configs     don't touch ~/.gitconfig or ~/.config/{bat,btop,glow,git,lazygit}
#   --skip-shell       don't touch ~/.bashrc
#   --claude-code      also install the Claude Code CLI (login stays manual)
#   --claudex          also install CLIProxyAPI + the claudex harness (opt-in;
#                      needs a one-time device-code login, see the notes it prints)
#   --t3               also install the T3 Code server + Codex CLI, write the
#                      nvm PATH shims, and register the supervised s6 services

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BEGIN_MARK='# >>> dotfiles linux >>>'
END_MARK='# <<< dotfiles linux <<<'

GIT_NAME=""
GIT_EMAIL=""
DO_TOOLS=1
DO_CLAUDE=1
DO_CONFIGS=1
DO_SHELL=1
DO_CLAUDE_CODE=0
DO_CLAUDEX=0
DO_T3=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --git-name)     GIT_NAME="${2:?--git-name needs a value}";   shift 2 ;;
        --git-email)    GIT_EMAIL="${2:?--git-email needs a value}"; shift 2 ;;
        --skip-tools)   DO_TOOLS=0;   shift ;;
        --skip-claude)  DO_CLAUDE=0;  shift ;;
        --skip-configs) DO_CONFIGS=0; shift ;;
        --skip-shell)   DO_SHELL=0;   shift ;;
        --claude-code)  DO_CLAUDE_CODE=1; shift ;;
        --claudex)      DO_CLAUDEX=1; shift ;;
        --t3)           DO_T3=1;      shift ;;
        -h|--help)      sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "bootstrap: unknown flag $1" >&2; exit 1 ;;
    esac
done

# The service layer -- run scripts in ~/.local/bin and s6 definitions in
# ~/.config/s6-user -- is installed whole, never per-service. Both --t3 and
# --claudex need part of it (t3-serve, cliproxyapi), and splitting it would
# mean a box that ran one flag has definitions referencing scripts the other
# flag installs. Registering a service is separate and idempotent, so copying
# a definition you do not use costs nothing.
install_service_layer() {
    echo "==> Installing supervised-service scripts"
    mkdir -p ~/.local/bin ~/.config/s6-user ~/.config/t3
    for f in "$REPO"/linux/bin/*; do
        install -m 755 "$f" ~/.local/bin/"$(basename "$f")"
    done
    cp -r "$REPO"/linux/s6-user/. ~/.config/s6-user/
    chmod +x ~/.config/s6-user/*/run ~/.config/s6-user/*/finish ~/.config/s6-user/*/check
    echo "    ~/.local/bin + ~/.config/s6-user populated"
}

# AWS CLI v2 ships as a bundled installer behind a zip, not as a GitHub
# Release asset, so it cannot join the install-tools.sh fetcher the way the
# static binaries do -- the same reason Claude Code has its own section
# below. The installer owns its install dir and symlinks `aws` and
# `aws_completer` into the bin dir.
#
# Both dirs are under $HOME even though these boxes do have sudo. A
# /usr/local install would not survive a pod restart: only $HOME is
# persistent here, everything else comes back from the image.
#
# No credential is provisioned. Signing in is a one-time interactive step
# per box, documented in linux/README.md.
install_awscli() {
    local install_dir="$HOME/.local/aws-cli" bin_dir="$HOME/.local/bin"
    local url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
    local tmp update=()

    echo "==> Installing AWS CLI v2"
    if ! command -v unzip >/dev/null 2>&1; then
        echo "    skipped -- unzip not found" >&2
        return 0
    fi

    # The bundled installer rejects --update on a first run and requires it
    # on every later one, so the flag is chosen from what is already there.
    # This is what AWS's own downloader script does.
    if [[ -e "$bin_dir/aws" ]]; then
        update=(--update)
    fi

    tmp="$(mktemp -d)"
    curl -fsSL "$url" -o "$tmp/awscliv2.zip"
    unzip -q "$tmp/awscliv2.zip" -d "$tmp"
    mkdir -p "$install_dir" "$bin_dir"
    "$tmp/aws/install" --install-dir "$install_dir" --bin-dir "$bin_dir" "${update[@]}"
    rm -rf "$tmp"

    printf '    %s\n' "$("$bin_dir/aws" --version 2>&1 | head -1)"
}

# ── 1. CLI binaries ────────────────────────────────────────
if [[ "$DO_TOOLS" == 1 ]]; then
    echo "==> Installing CLI tools"
    if [[ "$DO_CLAUDEX" == 1 ]]; then
        "$REPO/linux/install-tools.sh" --with-claudex
    else
        "$REPO/linux/install-tools.sh"
    fi
    echo
    install_awscli
    echo
fi

# ── 2. Claude Code ─────────────────────────────────────────
# Opt-in behind --claude-code, and deliberately not part of
# install-tools.sh: that fetcher resolves GitHub Release assets, while
# Claude Code ships through its own installer, which owns
# ~/.local/share/claude/versions and the ~/.local/bin/claude launcher.
# Re-running upgrades in place, so this is also the upgrade path.
#
# The installer only places the binary. Authenticating is a separate
# interactive step: run `claude` once and follow the code flow it prints.
if [[ "$DO_CLAUDE_CODE" == 1 ]]; then
    echo "==> Installing Claude Code"
    if command -v claude >/dev/null 2>&1; then
        printf '    currently %s\n' "$(claude --version 2>/dev/null | head -1)"
    fi
    curl -fsSL https://claude.ai/install.sh | bash
    printf '    now %s\n' "$(~/.local/bin/claude --version 2>/dev/null | head -1 || echo installed)"
    echo
fi

# ── 3. Claude config ───────────────────────────────────────
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

# ── 4. Tool configs + git ──────────────────────────────────
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

# ── 5. Shell ───────────────────────────────────────────────
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

    # Per-machine settings live outside version control. bashrc.linux sources
    # ~/.config/bash/local.bash if it exists; nothing seeds it any more.
    [[ -f ~/.config/bash/local.bash ]] || touch ~/.config/bash/local.bash

    echo
fi

# ── 6. claudex + CLIProxyAPI ───────────────────────────────
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

    install_service_layer
    if [[ -d /var/run/s6/services ]]; then
        ~/.local/bin/s6-user-services-install
    fi

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

# ── 7. T3 Code + supervised services ───────────────────────
# T3 Code drives agent sessions against this box from a browser or phone.
# `t3 service install` writes a systemd unit and these boxes have no systemd,
# so s6 supervises it, the same way it supervises the proxy.
#
# Everything here is idempotent, so this is also the upgrade path. Logging in
# is not done here: `t3 connect link --headless` is a one-time interactive
# step, and so is `codex login`.
if [[ "$DO_T3" == 1 ]]; then
    install_service_layer

    echo "==> Installing node PATH shims"
    ~/.local/bin/nvm-shims-install
    export PATH="$HOME/.local/bin:$PATH"

    echo "==> Installing t3 + codex"
    if ! command -v node >/dev/null 2>&1; then
        echo "    ERROR: no node under ~/.config/nvm/versions/node — install one with nvm first" >&2
        exit 1
    fi
    # --allow-scripts is load-bearing: npm skips install scripts by default, and
    # without node-pty's build `t3 serve` dies the moment it opens a terminal.
    #
    # Track whatever channel the desktop app is on: a nightly client talking to
    # a stable server shows a "server update available" banner it cannot act on,
    # because remote updates go through `t3 service install` and that wants
    # systemd. An env var rather than a flag -- it selects a version of one
    # package, which is not the kind of choice the other flags make.
    #   T3_CHANNEL=nightly ~/.dotfiles/linux/bootstrap.sh --t3
    T3_CHANNEL="${T3_CHANNEL:-latest}"
    npm i -g --allow-scripts=msgpackr-extract,node-pty "t3@${T3_CHANNEL}" @openai/codex
    printf '    t3 %s, codex %s\n' "$(t3 --version 2>/dev/null)" "$(codex --version 2>/dev/null)"

    # How the server is exposed is per-box, so it is never overwritten.
    if [[ ! -f ~/.config/t3/serve.env ]]; then
        cat > ~/.config/t3/serve.env <<'ENV'
# Sourced by ~/.local/bin/t3-serve-run. Per-box, never committed.
#
# Loopback only. With T3 Connect the tunnel is established by `t3 serve`
# itself once `t3 connect link --headless` has been run, so this stays as is.
T3_SERVE_ARGS="--host 127.0.0.1"
ENV
        echo "    ~/.config/t3/serve.env seeded (loopback)"
    fi

    if [[ -d /var/run/s6/services ]]; then
        echo "==> Registering s6 services"
        ~/.local/bin/s6-user-services-install
    else
        echo "    no /var/run/s6/services — not an s6 box, skipping registration"
    fi

    echo
    echo "    ONE-TIME LOGINS REQUIRED (interactive, not done here):"
    echo "      t3 connect link --headless   # prints a URL; authorizes this environment"
    echo "      codex login                  # device-code flow for the native Codex CLI"
    echo "    Then restart the server so it picks the link up:"
    echo "      s6-svc -r /var/run/s6/services/t3-serve"
    echo
fi

echo "==> Done. Open a new shell, or: source ~/.bashrc"
