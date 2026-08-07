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

# Open a GitHub PR's diff in hunk without checking the branch out.
# Fetches the PR head into refs/prdiff/pr-<N> (forced, survives rebases) and
# diffs from the merge-base with the PR's base branch — same view as the
# "Files changed" tab on github.com.
#
# Usage: prdiff <pr-number>
prdiff() {
    local pr="$1"
    if [[ -z "$pr" ]]; then
        echo "usage: prdiff <pr-number>" >&2
        return 1
    fi

    local base
    base=$(gh pr view "$pr" --json baseRefName -q .baseRefName) || return 1

    git fetch --quiet origin "$base" "+refs/pull/$pr/head:refs/prdiff/pr-$pr" || return 1

    local mb
    mb=$(git merge-base "origin/$base" "refs/prdiff/pr-$pr") || return 1

    hunk diff "$mb..refs/prdiff/pr-$pr"
}
