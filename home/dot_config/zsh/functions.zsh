# ~/.config/zsh/functions.zsh — user-defined shell functions.
# Add functions here as needed.

# yazi shell wrapper. Quitting yazi with `q` writes the last-visited
# dir to --cwd-file; we then `cd` there so the shell follows yazi's
# navigation. Invoke as `y` (rather than `yazi`) to get this behaviour.
y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
    yazi "$@" --cwd-file="$tmp"
    if cwd="$(command cat -- "$tmp")" && [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
        builtin cd -- "$cwd"
    fi
    rm -f -- "$tmp"
}
