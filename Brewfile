# Tools required to bootstrap and operate this dotfiles setup.
# Add more as needed; keeping minimal so a fresh-machine install
# doesn't pull in opinions you didn't ask for.

# Bootstrap
brew "chezmoi"
brew "antidote"

# Python tooling
brew "uv"         # Python package & tool manager; installs global CLIs
                  # (e.g. TrueFoundry `tfy`) via run_once_after_uv-tools script

# Node tooling
brew "node"       # runtime for the global npm CLIs installed by the
                  # run_once_after_npm-tools script (hunkdiff, which provides
                  # the `hunk` that functions.zsh's prdiff shells out to)

# Modern CLI replacements (aliased in dot_config/zsh/aliases.zsh)
brew "bat"        # cat
brew "eza"        # ls
brew "fd"         # find
brew "ripgrep"    # grep
brew "btop"       # top / htop

# Shell integrations (sourced in dot_config/zsh/dot_zshrc)
brew "fzf"        # fuzzy finder (Ctrl-R, Ctrl-T, Alt-C)
brew "zoxide"     # smart cd (z, zi)
brew "jq"         # dot_claude/scripts/context-bar.sh parses the statusline
                  # payload with it, so the Claude Code statusline breaks
                  # without it. Distinct from jless, which only views JSON.

# Git
brew "git-delta"  # syntax-highlighted git diffs
brew "lazygit"    # git TUI (alias: lzh)
brew "gh"         # GitHub CLI; the prdiff function in functions.zsh calls it
brew "gnupg"      # dot_gitconfig.tmpl sets gpgsign = true whenever a
                  # signing key is configured, so without gpg every commit
                  # on a fresh machine fails outright
brew "pinentry-mac" # macOS passphrase prompt gpg needs to unlock that key

# Containers
brew "lazydocker" # docker TUI (alias: lzd)

# Terminal-first replacements for GUI departures
brew "yazi"       # file manager TUI
brew "xh"         # HTTP client (Postman/Insomnia replacement)
brew "jless"      # interactive JSON viewer
brew "glow"       # markdown renderer
brew "chafa"      # image-in-terminal preview
brew "mpv"        # audio/video player (wired into yazi opener)
brew "moor"       # Rust-based less replacement (set as $PAGER) with
                  # native mouse/trackpad scroll support

# GUI apps this repo carries config for. Declared not as preference but
# because the config deploys either way: without the app it lands with
# nothing to read it, and without the font the prompt renders as tofu.
cask "zed"                      # $EDITOR / $VISUAL in dot_zshenv and git
                                # core.editor; settings in dot_config/zed
cask "cmux"                     # settings in dot_config/cmux
cask "karabiner-elements"       # settings in dot_config/private_karabiner
cask "font-fira-code-nerd-font" # glyphs both the mynk.zsh prompt and zed's
                                # configured font family ask for

# Cloud / data platforms
tap "databricks/tap"
brew "databricks" # Databricks CLI

# AI tooling
brew "cliproxyapi" # fronts Gemini CLI, Codex, Claude Code and Qwen Code with
                   # one OpenAI-compatible endpoint on :8317. Runs as a login
                   # service (`brew services start cliproxyapi`); its config
                   # (/opt/homebrew/etc/cliproxyapi.conf) and provider logins
                   # (~/.cli-proxy-api) stay untracked — this repo is public

# Networking
brew "proxytunnel"     # tunnel TCP connections through HTTPS proxies
cask "wireshark-app"   # packet analyzer; bundles the CLI tools (tshark,
                       # dumpcap, editcap, capinfos) plus ChmodBPF, without
                       # which the capture-interface list comes up empty
