# Tools required to bootstrap and operate this dotfiles setup.
# Add more as needed; keeping minimal so a fresh-machine install
# doesn't pull in opinions you didn't ask for.

# Bootstrap
brew "chezmoi"
brew "antidote"

# Python tooling
brew "uv"         # Python package & tool manager; installs global CLIs
                  # (e.g. TrueFoundry `tfy`) via run_once_after_uv-tools script

# Modern CLI replacements (aliased in dot_config/zsh/aliases.zsh)
brew "bat"        # cat
brew "eza"        # ls
brew "fd"         # find
brew "ripgrep"    # grep
brew "btop"       # top / htop

# Shell integrations (sourced in dot_config/zsh/dot_zshrc)
brew "fzf"        # fuzzy finder (Ctrl-R, Ctrl-T, Alt-C)
brew "zoxide"     # smart cd (z, zi)

# Git
brew "git-delta"  # syntax-highlighted git diffs
brew "lazygit"    # git TUI (alias: lzh)

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

# Cloud / data platforms
tap "databricks/tap"
brew "databricks" # Databricks CLI

# Networking
brew "proxytunnel" # tunnel TCP connections through HTTPS proxies
