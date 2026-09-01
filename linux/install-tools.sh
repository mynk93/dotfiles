#!/usr/bin/env bash
# linux/install-tools.sh — fetch static CLI binaries into ~/.local/bin.
#
# Built for rootless boxes (k8s dev pods, shared VMs) where there is no
# sudo and no usable package manager. Every tool below publishes a
# self-contained x86_64 Linux binary on GitHub Releases, so we resolve the
# latest tag through the API, unpack to a temp dir, and move just the
# binary into place. Re-running upgrades in place.
#
# Override the destination with BIN=/somewhere ./install-tools.sh

set -euo pipefail

BIN="${BIN:-$HOME/.local/bin}"

arch="$(uname -m)"
if [[ "$arch" != "x86_64" ]]; then
    echo "install-tools: only x86_64 is supported, found $arch" >&2
    exit 1
fi

mkdir -p "$BIN"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# repo | asset filename (extended regex, anchored) | binary inside it
TOOLS=(
    "eza-community/eza|eza_x86_64-unknown-linux-gnu.tar.gz|eza"
    "sharkdp/bat|bat-v.+-x86_64-unknown-linux-gnu.tar.gz|bat"
    "sharkdp/fd|fd-v.+-x86_64-unknown-linux-gnu.tar.gz|fd"
    "BurntSushi/ripgrep|ripgrep-.+-x86_64-unknown-linux-musl.tar.gz|rg"
    "junegunn/fzf|fzf-.+-linux_amd64.tar.gz|fzf"
    "ajeetdsouza/zoxide|zoxide-.+-x86_64-unknown-linux-musl.tar.gz|zoxide"
    "dandavison/delta|delta-.+-x86_64-unknown-linux-gnu.tar.gz|delta"
    "charmbracelet/glow|glow_.+_Linux_x86_64.tar.gz|glow"
    "jqlang/jq|jq-linux-amd64|jq"
)

# Pick the one release asset whose filename matches, without needing jq —
# jq is itself one of the things we may be installing.
resolve_asset_url() {
    local repo="$1" pattern="$2"
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | grep -oE '"browser_download_url":[[:space:]]*"[^"]+"' \
        | sed -E 's/.*"(https[^"]+)"$/\1/' \
        | grep -E "/${pattern}$" \
        | head -1
}

install_tool() {
    local repo="$1" pattern="$2" bin="$3"
    local url work found

    url="$(resolve_asset_url "$repo" "$pattern" || true)"
    if [[ -z "$url" ]]; then
        printf '  %-8s skipped — no asset matching %s in the latest release\n' "$bin" "$pattern"
        return 0
    fi

    work="$TMP/$bin"
    mkdir -p "$work"

    if [[ "$url" == *.tar.gz ]]; then
        curl -fsSL "$url" | tar -xz -C "$work"
        # Release layouts differ (some nest under a versioned dir), so search.
        found="$(find "$work" -type f -name "$bin" | head -1)"
        if [[ -z "$found" ]]; then
            printf '  %-8s failed — %s not found inside the archive\n' "$bin" "$bin"
            return 0
        fi
    else
        found="$work/$bin"
        curl -fsSL "$url" -o "$found"
    fi

    install -m 755 "$found" "$BIN/$bin"
    printf '  %-8s %s\n' "$bin" "$("$BIN/$bin" --version 2>/dev/null | head -1 || echo installed)"
}

echo "Installing static binaries into $BIN"
for entry in "${TOOLS[@]}"; do
    IFS='|' read -r repo pattern bin <<<"$entry"
    install_tool "$repo" "$pattern" "$bin"
done

echo
echo "Done. Ensure $BIN is on PATH (bashrc.linux exports it)."
