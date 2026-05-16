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

# Windows-style `explorer <path>` to open in Finder (macOS `open`).
alias explorer='open'

# System monitor — btop replaces top/htop.
alias top='btop'
alias htop='btop'

# Network
alias ip="ipconfig getifaddr en0"

# Reload / edit shell config
alias zshsource="source ${ZDOTDIR:-$HOME}/.zshrc"
alias zshconfig="zed ${ZDOTDIR:-$HOME}/.zshrc"

# Navigation
alias sshhome="cd ~/.ssh"
alias awshome="cd ~/.aws"
alias cconfig="cd ~/.claude && zed ."
alias phome="cd ~/dev/work"
alias sandbox="cd ~/sandbox"

# Edit common configs
alias sshconfig="zed ~/.ssh/config"
alias gitconfig="zed ~/.gitconfig"

# Tooling shortcuts
alias cc="claude"
alias lzh="lazygit"
alias lzd="lazydocker"

# Project scripts
alias agentorc="~/dev/work/scripts/agentorc.sh"
