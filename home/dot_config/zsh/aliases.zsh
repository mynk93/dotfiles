# ~/.config/zsh/aliases.zsh — user-defined aliases.

# Directory listing. `ls` is aliased to eza; the shorthands below inherit
# via zsh's recursive alias expansion (l → ls -lah → eza -lah).
alias ls='eza'
alias l='ls -lah'
alias la='ls -lAh'
alias ll='ls -lh'
alias lsa='ls -lah'

# File viewing — bat replaces cat (syntax highlighting + paging).
alias cat='bat'

# Markdown rendering — `view file.md` for a paged glow render.
alias view='glow -p'

# Searching — `grep` is intentionally NOT aliased to `rg`. The CLI gap
# is large (-E, -P, --include, recursion semantics) and aliasing creates
# more surprises than it solves. Use `rg` directly for ripgrep features.

# File finding — fd replaces find. `fd PATTERN` instead of `find . -name PATTERN`.
alias find='fd'

# Windows-style `explorer <path>`: Finder on macOS, the desktop's default
# handler on Linux.
if [[ "$OSTYPE" == darwin* ]]; then
    alias explorer='open'
else
    alias explorer='xdg-open'
fi

# System monitor — btop replaces top/htop.
alias top='btop'
alias htop='btop'

# Network. macOS only: on Linux `ip` is iproute2, and shadowing it breaks
# `ip a` and `ip route`.
[[ "$OSTYPE" == darwin* ]] && alias ip="ipconfig getifaddr en0"

# Reload / edit shell config. zed on macOS; $EDITOR (vim) where there is no
# GUI editor.
alias zshsource="source ${ZDOTDIR:-$HOME}/.zshrc"
if [[ "$OSTYPE" == darwin* ]]; then
    alias zshconfig="zed ${ZDOTDIR:-$HOME}/.zshrc"
    alias cconfig="cd ~/.claude && zed ."
    alias sshconfig="zed ~/.ssh/config"
    alias gitconfig="zed ~/.gitconfig"
else
    alias zshconfig="\$EDITOR ${ZDOTDIR:-$HOME}/.zshrc"
    alias cconfig="cd ~/.claude"
    alias sshconfig="\$EDITOR ~/.ssh/config"
    alias gitconfig="\$EDITOR ~/.gitconfig"
fi

# Navigation
alias sshhome="cd ~/.ssh"
alias awshome="cd ~/.aws"
alias phome="cd ~/dev/work"
alias sandbox="cd ~/sandbox"

# Tooling shortcuts
alias cc="claude"
alias lzh="lazygit"
alias lzd="lazydocker"
alias dbx="databricks"

# Project scripts
alias agentorc="~/dev/work/scripts/agentorc.sh"
