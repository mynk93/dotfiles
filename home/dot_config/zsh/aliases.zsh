# ~/.config/zsh/aliases.zsh — user-defined aliases.

# Directory listing (mirrors what OMZ's lib/directories.zsh used to provide).
alias l='ls -lah'
alias la='ls -lAh'
alias ll='ls -lh'
alias lsa='ls -lah'

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
alias lzd="lazygit"

# Project scripts
alias agentorc="~/dev/work/scripts/agentorc.sh"
