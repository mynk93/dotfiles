# Custom Zsh prompt — translated from an Oh My Posh theme.
# Requires a Nerd Font in the terminal (Hack NF, FiraCode NF, etc.).

autoload -Uz vcs_info
autoload -Uz add-zsh-hook

# $EPOCHREALTIME (used by the duration timer) lives in zsh/datetime.
zmodload zsh/datetime

setopt PROMPT_SUBST

# Path → glyph overrides. Hybrid behavior in _build_prompt:
#   - if CWD == key: replace path display with glyph (no parent shown)
#   - if CWD's parent == key: parent slot shows glyph, current as normal
typeset -gA _PATH_GLYPHS
_PATH_GLYPHS[$HOME/dev/work]='⚙'

# ── Colours ─────────────────────────────────────────────────
# Map hex values to closest 256-colour or use truecolor if supported.
# Background: #18354c  → dark navy
# Foreground: #ffc107  → amber
# These use Zsh's %F{} / %K{} with truecolor escape wrappers.

_bg_navy()  { printf '\e[48;2;24;53;76m' }    # #18354c
_fg_amber() { printf '\e[38;2;255;193;7m' }   # #ffc107
_fg_navy()  { printf '\e[38;2;24;53;76m' }    # #18354c
_reset()    { printf '\e[0m' }
_bold()     { printf '\e[1m' }

# Powerline glyphs
PL_RIGHT=$'\ue0b0'   # solid right arrow
PL_LEFT=$'\ue0b2'    # solid left arrow
PL_LD=$'\ue0b6'      # left rounded  (leading diamond)
PL_RD=$'\ue0b4'      # right rounded  (trailing diamond)
PL_FOLDER=$'\ue5ff'  # nerd font folder icon
PL_CLOCK=$'\uf017'   # clock icon
PL_TIMER=$'\uf252'   # hourglass icon
PL_ROOT=$'\uf0e7'    # lightning bolt (root indicator)

# ── Execution time tracking ──────────────────────────────────
_cmd_start_time=0

_prompt_preexec() {
    _cmd_start_time=$EPOCHREALTIME
}

_format_duration() {
    # Don't render anything if no command has been tracked yet
    if (( _cmd_start_time == 0 )); then
        return
    fi

    # local -i forces integer storage so float values from $EPOCHREALTIME
    # are truncated; otherwise `h` becomes a tiny positive float and the
    # `(( h > 0 ))` branch fires for sub-second commands → "0m 0s".
    local -i elapsed_ms=$(( ($EPOCHREALTIME - $_cmd_start_time) * 1000 ))
    local -i ms=$(( elapsed_ms % 1000 ))
    local -i s=$(( (elapsed_ms / 1000) % 60 ))
    local -i m=$(( (elapsed_ms / 60000) % 60 ))
    local -i h=$(( elapsed_ms / 3600000 ))

    if (( h > 0 ));    then printf '%dm %ds' $m $s
    elif (( m > 0 ));  then printf '%dm %ds' $m $s
    elif (( s >= 5 )); then printf '%ds' $s
    elif (( elapsed_ms > 0 )); then printf '%dms' $elapsed_ms
    fi
    # Note: don't reset _cmd_start_time here — this function runs in a
    # subshell via command substitution, so the assignment wouldn't stick.
    # The reset lives in _prompt_precmd below.
}

add-zsh-hook preexec _prompt_preexec

# ── Git info via vcs_info ────────────────────────────────────
zstyle ':vcs_info:git:*' enable git
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' unstagedstr '✗'
zstyle ':vcs_info:git:*' stagedstr '✔'
# Format: branch [staged][unstaged]
zstyle ':vcs_info:git:*' formats       ' %b %u%c'
zstyle ':vcs_info:git:*' actionformats ' %b|%a %u%c'

_prompt_precmd() {
    vcs_info
    _build_prompt
    # Reset the timer anchor so empty Enters (no preexec firing) don't
    # keep showing growing durations against an old anchor.
    _cmd_start_time=0
}

add-zsh-hook precmd _prompt_precmd

# ── Path helpers ─────────────────────────────────────────────
_path_parent() {
    # Returns the parent directory name. If the absolute parent path is in
    # _PATH_GLYPHS, return its glyph instead.
    local parent="${PWD:h}"
    if [[ -n "${_PATH_GLYPHS[$parent]}" ]]; then
        echo "${_PATH_GLYPHS[$parent]}"
        return
    fi
    parent="${parent/#$HOME/🏡}"
    [[ "$parent" == "/" ]] && parent="" || parent="${parent##*/}"
    echo "$parent"
}

_path_current() {
    # Current folder name; root = /
    [[ "$PWD" == "/" ]] && echo "/" || echo "${PWD##*/}"
}

# ── Prompt builder ───────────────────────────────────────────
_build_prompt() {
    local reset=$'%{\e[0m%}'
    local bg_navy=$'%{\e[48;2;24;53;76m%}'
    local fg_amber=$'%{\e[38;2;255;193;7m%}'
    local fg_navy=$'%{\e[38;2;24;53;76m%}'
    local fg_white=$'%{\e[97m%}'
    local bg_amber=$'%{\e[48;2;255;193;7m%}'
    local bg_reset=$'%{\e[49m%}'

    # ── Left: line 1 ──────────────────────────────────────────
    local prefix="⚽📸 "

    # Leading rounded backstop. PL_LD rendered in navy fg on default bg
    # so it reads as the rounded left edge of the navy pill itself.
    local seg_path_open="${reset}${fg_navy}${PL_LD}${bg_navy}${fg_amber}"
    local seg_parent seg_current

    # Hybrid path mapping: if CWD itself is mapped, collapse the whole
    # path display to a single glyph segment.
    if [[ -n "${_PATH_GLYPHS[$PWD]}" ]]; then
        seg_parent=""
        seg_current="${seg_path_open}${PL_FOLDER} ${_PATH_GLYPHS[$PWD]} "
    else
        local parent="$(_path_parent)"
        local current="$(_path_current)"
        seg_parent="${seg_path_open} ${parent} "
        seg_current="${bg_navy}${fg_amber}${PL_FOLDER} ${current} "
    fi

    # Git segment (stays on navy background, same palette)
    local git_info=""
    if [[ -n "${vcs_info_msg_0_}" ]]; then
        git_info="${bg_navy}${fg_amber}│${vcs_info_msg_0_} "
    fi

    # Closing arrow: navy → default bg, rendered as amber arrow-on-default.
    # This is the tail of the path/git block.
    local seg_close="${reset}${fg_navy}${PL_RIGHT}${reset}"

    # Root indicator: ONLY render when actually root. Otherwise nothing.
    local root_seg=""
    if [[ $EUID -eq 0 ]]; then
        root_seg="${bg_amber}${fg_navy} ${PL_ROOT} ${reset}${fg_amber}${PL_RIGHT}${reset}"
    fi

    # Raw colour escapes (NOT wrapped in %{...%}). The whole RPROMPT
    # below is wrapped in a single %{...%} so zsh treats it as zero-width.
    # That lets us position both line-1-right and line-2-right by absolute
    # column ourselves, sidestepping zsh's emoji/PUA width estimation.
    local _raw_fa=$'\e[38;2;255;193;7m'
    local _raw_ba=$'\e[48;2;255;193;7m'
    local _raw_fn=$'\e[38;2;24;53;76m'
    local _raw_rs=$'\e[0m'

    # ── Line 1 right: execution time + clock ──────────────────
    # Per pill width: PL_LEFT(1) + space(1) + content + space(1) + icon(1)
    # + space(1) = 5 + len(content). Last pill adds PL_RD backstop = +1.
    local duration="$(_format_duration)"
    local clock_text="$(date '+%-I:%M:%S %p')"
    local rhs_raw=""
    local rhs_width=0
    if [[ -n "$duration" ]]; then
        rhs_raw+="${_raw_fa}${PL_LEFT}${_raw_ba}${_raw_fn} ${duration} ${PL_TIMER} "
        rhs_width=$(( rhs_width + 5 + ${#duration} ))
    fi
    rhs_raw+="${_raw_fa}${PL_LEFT}${_raw_ba}${_raw_fn} ${clock_text} ${PL_CLOCK} ${_raw_rs}${_raw_fa}${PL_RD}${_raw_rs}"
    rhs_width=$(( rhs_width + 6 + ${#clock_text} ))
    local rhs_target_col=$(( COLUMNS - rhs_width + 1 ))
    (( rhs_target_col < 1 )) && rhs_target_col=1

    # ── Line 2 right: venv ────────────────────────────────────
    # Width: PL_LEFT(1) + space(1) + 🐍(2) + space(1) + name + space(1)
    # + PL_RD(1) = 7 + len(name).
    local venv_raw=""
    local venv_width=0
    if [[ -n "$VIRTUAL_ENV" ]]; then
        local venv_name="${VIRTUAL_ENV:t}"
        if [[ "$venv_name" == ".venv" || "$venv_name" == "venv" ]]; then
            venv_name="${VIRTUAL_ENV:h:t}"
        fi
        if (( ${#venv_name} > 20 )); then
            venv_name="${venv_name:0:19}…"
        fi
        venv_raw="${_raw_fa}${PL_LEFT}${_raw_ba}${_raw_fn} 🐍 ${venv_name} ${_raw_rs}${_raw_fa}${PL_RD}${_raw_rs}"
        venv_width=$(( 7 + ${#venv_name} ))
    fi

    # Single zero-width RPROMPT block. Sequence:
    #   \e[1A — up to line 1
    #   \e[<col>G — abs-position for line 1 right
    #   <rhs>    — draw timer+clock
    #   \e[1B — down to line 2
    #   (if venv) \e[<col>G then <venv> — draw venv right-aligned
    # Net cursor lands on line 2 at col COLUMNS+1, which is where zsh
    # expects the cursor after a zero-width RPROMPT. Tracking matches
    # reality, so redraws don't drift.
    local block_inner=$'\e[1A\e['"${rhs_target_col}"$'G'"${rhs_raw}"$'\e[1B'
    if [[ -n "$venv_raw" ]]; then
        local venv_target_col=$(( COLUMNS - venv_width + 1 ))
        (( venv_target_col < 1 )) && venv_target_col=1
        block_inner+=$'\e['"${venv_target_col}"$'G'"${venv_raw}"
    fi
    RPROMPT=$'%{'"${block_inner}"$'%}'

    PROMPT="${prefix}${seg_parent}${seg_current}${git_info}${seg_close}${root_seg}"$'\n'"🚀 ❯ "
}

# ── Transient prompt ─────────────────────────────────────────
# After a command runs, collapse the prompt to the minimal form.
# Requires the zsh-vi-mode plugin or a manual TRAPINT, so here we
# use a simpler approach: just keep a compact PROMPT2 for continuation lines.
PROMPT2="  ❯ "
