#!/usr/bin/env bash
# linux/clone-work-repos.sh — clone the prodigal-tech work checkout.
#
# Deliberately NOT called by bootstrap.sh. It needs a GitHub credential
# bootstrap does not create: generate a key on the box, point
# ~/.ssh/config at it, and register the public half with GitHub. Without
# that every clone fails at once, so this stays a separate step you run
# once the key is live.
#
# Idempotent: an existing clone is left alone and a path that exists but
# isn't a repo is reported and skipped, so re-running only fills gaps.
#
# Overrides: WORK=/elsewhere ORG=git@github.com:other JOBS=2 ./clone-work-repos.sh
set -uo pipefail

WORK="${WORK:-$HOME/dev/work}"
ORG="${ORG:-git@github.com:prodigal-tech}"
JOBS="${JOBS:-6}"
LOG="$WORK/.clone-report.txt"
ERR="$WORK/.clone-errors.txt"

REPOS=(
  agent-orchestrator
  aura-agent-control
  crm-core
  langfuse-proagent
  manthan-sdk
  payments-core
  portal-app
  portal-backend
  proagent-apis
  proagent-call-queue-manager
  proagent-mock-data-server
  proagent-oven
  proagent-plugins
  proagent-test-tracker-backend
  proagent-utils
  proagent-versions
  proagent-web-demo
  prodigal-context-graph
  prodigal-home-backend
  prodigal-home-frontend
  prodigal-knowledge-hub
  python-codeserver
  voice-flask-backend
  voice-frontend
)

clone_one() {
  local repo="$1" work="$2" log="$3" err="$4" org="$5"
  local dest="$work/$repo" branch

  if git -C "$dest" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$dest" rev-parse --abbrev-ref HEAD 2>/dev/null)
    printf 'SKIP     %-32s already cloned (%s)\n' "$repo" "$branch" | tee -a "$log"
    return 0
  fi
  if [ -e "$dest" ]; then
    printf 'BLOCKED  %-32s path exists but is not a git repo\n' "$repo" | tee -a "$log"
    return 1
  fi

  printf '...      %-32s cloning\n' "$repo"
  # GIT_TERMINAL_PROMPT=0 so a missing credential fails fast instead of
  # blocking 24 parallel clones on a username prompt.
  if GIT_TERMINAL_PROMPT=0 git clone --quiet "$org/$repo.git" "$dest" 2>>"$err"; then
    branch=$(git -C "$dest" rev-parse --abbrev-ref HEAD 2>/dev/null)
    printf 'OK       %-32s cloned (%s)\n' "$repo" "$branch" | tee -a "$log"
  else
    printf 'FAIL     %-32s see %s\n' "$repo" "$err" | tee -a "$log"
    return 1
  fi
}
export -f clone_one

mkdir -p "$WORK"
: > "$LOG"
: > "$ERR"

echo "Cloning ${#REPOS[@]} repos from $ORG into $WORK ($JOBS at a time)"
echo "----------------------------------------------------------------"
printf '%s\n' "${REPOS[@]}" \
  | xargs -P "$JOBS" -I{} bash -c 'clone_one "$@"' _ {} "$WORK" "$LOG" "$ERR" "$ORG"

echo "----------------------------------------------------------------"
sort "$LOG"
printf '\nSUMMARY: %s cloned, %s already present, %s blocked, %s failed  (of %s)\n' \
  "$(grep -c '^OK' "$LOG")" "$(grep -c '^SKIP' "$LOG")" \
  "$(grep -c '^BLOCKED' "$LOG")" "$(grep -c '^FAIL' "$LOG")" "${#REPOS[@]}"
echo "Disk:"; df -h "$HOME" | tail -1
[ -s "$ERR" ] && { echo; echo "git stderr:"; cat "$ERR"; }
exit 0
