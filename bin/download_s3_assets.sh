#!/usr/bin/env bash
###############################################################################
# download_s3_assets.sh
# S3 Object downloader with MRU state (bucket, prefix, profile, selection)
# Browses buckets/folders interactively when values are unset or 'default'
#
# Non-interactive / scripted use:
#   download_s3_assets.sh '<json>'
#   download_s3_assets.sh --config '<json>'
#   download_s3_assets.sh --config-file path/to/config.json
#
# JSON config fields (all optional - any field present skips its prompt):
#   {
#     "PROFILE": "aws-profile-name",
#     "BUCKET":  "bucket-name",
#     "PREFIX":  "folder/path",
#     "Objects": ["file1.txt", "sub/file2.txt"]
#   }
#
# The same schema is used to persist ~/.download_s3_assets.mru between runs.
# "Objects" (both in a supplied config and in the MRU file) is always stored
# as paths *relative to PREFIX* - never the full "prefix/file" key - so the
# prefix isn't represented twice (once as its own field, once baked into the
# front of every stored path).
###############################################################################
set -uo pipefail

readonly MRU_FILE="${HOME}/.download_s3_assets.mru"
readonly LOGFILE="${HOME}/download_s3_assets.$(date +%Y%m%d-%H%M%S).log"
START_TIME=$(date +%s)

# ANSI
readonly Reset="\033[0m" Bold="\033[1m"
readonly Red="\033[31m" Green="\033[32m" Yellow="\033[33m" Blue="\033[34m" White="\033[37m" Cyan="\033[36m"
readonly Clear="\033[2J" Home="\033[H" Hide="\033[?25l" Show="\033[?25h"
readonly Tick="✔" Cross="✘" Box="☐" Checked="☑"

AWS_PROFILE_NAME=""
BUCKET=""
PREFIX=""
DEST_DIR=""
YES="N"

declare -a FILES
declare -a SELECTED

# Config supplied on the command line (JSON). Any field present here is
# authoritative for this run and skips the corresponding prompt entirely.
CONFIG_JSON=""
CFG_PROFILE=""
CFG_BUCKET=""
CFG_PREFIX=""
CFG_DEST_DIR=""
declare -a CFG_OBJECTS=()
HAVE_CFG_PROFILE=0
HAVE_CFG_BUCKET=0
HAVE_CFG_PREFIX=0
HAVE_CFG_OBJECTS=0
HAVE_CFG_DEST_DIR=0

log() { printf "[%(%F %T)T] %s\n" -1 "$*" >>"$LOGFILE"; }

require_jq() {
    command -v jq >/dev/null 2>&1 || {
        printf "${Red}This script requires 'jq' (e.g. 'brew install jq').${Reset}\n" >&2
        exit 1
    }
}

# Drain any keystrokes sitting unread in the terminal input buffer (e.g. an
# impatient Enter/keypress typed while a previous command was still running).
# Without this, that buffered key gets silently consumed by the *next*
# interactive read - which for pick_from_list means it looks like the menu
# "doesn't appear until you press Enter, and that Enter also selects an item".
flush_input() {
    while IFS= read -rsn 10000 -t 0.01 _ 2>/dev/null; do :; done
}

# Runs a command in the background and shows a live spinner (written straight
# to /dev/tty so it's visible even though the command's own stdout/stderr are
# being captured into a variable for logging/parsing).
run() {
    log "COMMAND: $*"
    local tmp rc output
    tmp=$(mktemp)

    # </dev/null is the key fix: if the underlying aws call ever needs to
    # prompt for input (expired SSO session, MFA, pager, anything), closing
    # its stdin makes that prompt hit EOF and fail immediately and visibly,
    # instead of blocking forever on input nobody can see or type into.
    "$@" </dev/null >"$tmp" 2>&1 &
    local pid=$!

    if [[ -t 1 ]]; then
        local spin='|/-\' i=0
        while kill -0 "$pid" 2>/dev/null; do
            printf "\r${Yellow}%s${Reset} working..." "${spin:i++%${#spin}:1}" >/dev/tty 2>/dev/null
            sleep 0.15
        done
        printf "\r%*s\r" 40 "" >/dev/tty 2>/dev/null
    fi

    wait "$pid"
    rc=$?
    output=$(<"$tmp")
    rm -f "$tmp"

    log "$output"
    log "RETURN=$rc"
    printf "%s" "$output"
    return $rc
}

cleanup() { printf "${Show}${Reset}"; }
trap cleanup EXIT

###############################################################################
# JSON config helpers (shared by --config/--config-file/inline CLI JSON, and
# by the JSON-formatted MRU file)
###############################################################################

# Rejects a value that contains a newline or ANSI escape byte, or is
# implausibly long. Those are the fingerprints of the old pick_from_list
# bug's corrupted output (a whole redrawn menu screen glued to the real
# value) - kept here as defense-in-depth so a corrupted/hand-edited MRU or
# config file can't silently poison a run.
sanitize_value() {
    local val=$1 max=${2:-1024}
    if [[ "$val" == *$'\n'* || "$val" == *$'\x1b'* || ${#val} -gt $max ]]; then
        return 1
    fi
    printf '%s' "$val"
}

# Extracts a top-level string field from a JSON blob. Succeeds only if the
# key is present and non-null (so an explicit "" is honored, but a missing
# key correctly falls through to the normal prompt/MRU flow instead of being
# treated as "explicitly set to empty").
json_field() {
    local json=$1 key=$2 max=${3:-1024} val sanitized
    jq -e --arg k "$key" 'has($k) and (.[$k] != null)' >/dev/null 2>&1 <<<"$json" || return 1
    val=$(jq -r --arg k "$key" '.[$k]' <<<"$json")
    sanitized=$(sanitize_value "$val" "$max") || {
        printf "${Yellow}Warning: ignoring suspicious value for '%s'${Reset}\n" "$key" >&2
        return 1
    }
    printf '%s' "$sanitized"
}

# Extracts the "Objects" array (list of strings, relative to PREFIX) from a
# JSON blob into the array named by $2. Succeeds if the key is present (even
# an empty array is a valid, deliberate "select nothing" instruction).
json_objects_field() {
    local json=$1
    local -n _out=$2
    jq -e 'has("Objects") and (.Objects != null)' >/dev/null 2>&1 <<<"$json" || return 1
    mapfile -t _out < <(jq -r '.Objects[]? // empty' <<<"$json")
    return 0
}

###############################################################################
# CLI argument / config parsing
###############################################################################
print_usage() {
    cat <<'EOF'
Usage:
  download_s3_assets.sh
  download_s3_assets.sh '<json config>'
  download_s3_assets.sh --config '<json config>'
  download_s3_assets.sh --config-file path/to/config.json

JSON config fields (all optional - any field present skips its prompt):
  {
    "PROFILE": "aws-profile-name",
    "BUCKET":  "bucket-name",
    "PREFIX":  "folder/path",
    "Objects": ["file1.txt", "sub/file2.txt"]
  }
EOF
}

parse_cli_args() {
    while [[ $# -gt 0 ]]; do
        case "${1:-}" in
            "") return 0 ;;
            --help|-h)
                print_usage
                exit 0
                ;;
            --config)
                CONFIG_JSON="${2:-}"
                shift
                shift
                ;;
            --config-file)
                [[ -n "${2:-}" && -f "${2:-}" ]] || { printf "${Red}Config file not found: %s${Reset}\n" "${2:-}" >&2; exit 1; }
                CONFIG_JSON=$(<"$2")
                shift
                shift
                ;;
            -y)
                YES="Y"
                shift
                ;;
            \{*)
                CONFIG_JSON="$1"
                shift
                ;;
            *)
                if [[ -f "$1" ]]; then
                    CONFIG_JSON=$(<"$1")
                    shift
                else
                    printf "${Red}Unrecognized argument: %s${Reset}\n" "$1" >&2
                    print_usage
                    exit 1
                fi
                ;;
        esac

        if [[ -n "$CONFIG_JSON" ]] && ! jq -e . >/dev/null 2>&1 <<<"$CONFIG_JSON"; then
            printf "${Red}Invalid JSON config provided.${Reset}\n" >&2
            exit 1
        fi
    done
}

# Populates CFG_* / HAVE_CFG_* from CONFIG_JSON. Anything set here is
# authoritative for this run and will skip its prompt in prompt_config().
apply_cli_config() {
    [[ -n "$CONFIG_JSON" ]] || return 0

    local v
    if v=$(json_field "$CONFIG_JSON" PROFILE 128); then CFG_PROFILE="$v"; HAVE_CFG_PROFILE=1; fi
    if v=$(json_field "$CONFIG_JSON" BUCKET 63);   then CFG_BUCKET="$v";  HAVE_CFG_BUCKET=1;  fi
    if v=$(json_field "$CONFIG_JSON" PREFIX 1024); then CFG_PREFIX="$v"; HAVE_CFG_PREFIX=1;  fi
    if v=$(json_field "$CONFIG_JSON" DEST_DIR 1024); then CFG_DEST_DIR="$v"; HAVE_CFG_DEST_DIR=1;  fi
    if json_objects_field "$CONFIG_JSON" CFG_OBJECTS; then HAVE_CFG_OBJECTS=1; fi
}

###############################################################################
# MRU state (JSON file: same schema as the CLI config, plus DEST_DIR)
###############################################################################
load_mru() {
    [[ -f "$MRU_FILE" ]] || return 0
    local json
    json=$(<"$MRU_FILE")

    if ! jq -e . >/dev/null 2>&1 <<<"$json"; then
        printf "${Yellow}Ignoring corrupted MRU file: %s${Reset}\n" "$MRU_FILE"
        return 0
    fi

    local v
    v=$(json_field "$json" PROFILE 128)  && AWS_PROFILE_NAME="$v"
    v=$(json_field "$json" BUCKET 63)    && BUCKET="$v"
    v=$(json_field "$json" PREFIX 1024)  && PREFIX="$v"
    v=$(json_field "$json" DEST_DIR 1024) && DEST_DIR="$v"
    # Objects in the MRU file is a historical record of the last download
    # only - it is NOT used to pre-select files on the next run. Use
    # --config/Objects (or the JSON positional arg) for that.
}

save_mru() {
    local -a selected_rel=()
    local i rel
    for ((i=0;i<${#FILES[@]};i++)); do
        (( SELECTED[i] )) || continue
        rel="${FILES[i]}"
        # Strip the current PREFIX so it isn't stored twice - once as its own
        # field, once baked into the front of every selected path.
        if [[ -n "$PREFIX" && "$rel" == "$PREFIX"* ]]; then
            rel="${rel#"$PREFIX"}"
        fi
        selected_rel+=("$rel")
    done

    local objects_json="[]"
    if (( ${#selected_rel[@]} > 0 )); then
        objects_json=$(printf '%s\n' "${selected_rel[@]}" | jq -R . | jq -s .)
    fi

    jq -n \
        --arg profile "$AWS_PROFILE_NAME" \
        --arg bucket "$BUCKET" \
        --arg prefix "$PREFIX" \
        --arg dest "$DEST_DIR" \
        --argjson objects "$objects_json" \
        '{PROFILE: $profile, BUCKET: $bucket, PREFIX: $prefix, DEST_DIR: $dest, Objects: $objects}' \
        > "$MRU_FILE"
}

###############################################################################
# Generic arrow-key picker: pass array name, prints choice to stdout, returns
# 1 if user quits/cancels. Supports a synthetic "[none / type manually]" entry
# when allow_manual=1.
###############################################################################
pick_from_list() {
    local -n _items=$1
    local title=$2
    local allow_manual=${3:-0}
    local count=${#_items[@]}
    local cursor=0 key

    if (( allow_manual )); then
        _items+=("[type manually]")
        ((count++))
    fi

    if (( count == 0 )); then
        return 1
    fi

    # Critical: this function's return value is read via `choice=$(pick_from_list ...)`.
    # Command substitution captures EVERY byte this function writes to fd1 (stdout),
    # not just the final chosen item - including every menu redraw on every
    # keystroke. Fix: all UI drawing goes straight to /dev/tty (bypasses capture,
    # always visible live); ONLY the final selected value is written to real stdout.
    exec 3>/dev/tty
    printf "${Hide}" >&3
    flush_input
    while true
    do
        printf "${Clear}${Home}" >&3
        printf "${Bold}${Cyan}%s${Reset}\n\n" "$title" >&3
        printf "Use:\n  ↑ ↓  Move\n  ENTER Select\n  q     Quit\n\n" >&3

        local i
        for ((i=0;i<count;i++))
        do
            if (( cursor==i )); then printf "${Blue}> ${Reset}" >&3; else printf "  " >&3; fi
            printf "%s\n" "${_items[i]}" >&3
        done

        IFS= read -rsn1 key
        case "$key" in
            "")
                printf "${Show}" >&3
                exec 3>&-
                printf "%s" "${_items[cursor]}"
                return 0
                ;;
            q) printf "${Show}" >&3; exec 3>&-; return 1 ;;
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    "[A") ((cursor--)) ;;
                    "[B") ((cursor++)) ;;
                esac
                ((cursor<0)) && cursor=0
                ((cursor>=count)) && cursor=$((count-1))
                ;;
        esac
    done
}

###############################################################################
# Browse buckets
###############################################################################
browse_bucket() {
    printf "${Yellow}Listing buckets (profile: %s)...${Reset}\n" "$AWS_PROFILE_NAME"
    local out
    if ! out=$(run aws --cli-connect-timeout 10 --cli-read-timeout 20 s3api list-buckets --profile "$AWS_PROFILE_NAME" --query 'Buckets[].Name' --output text)
    then
        printf "${Red}Unable to list buckets:${Reset}\n%s\n" "$out"
        return 1
    fi

    local -a buckets
    read -ra buckets <<< "$out"
    (( ${#buckets[@]} == 0 )) && { printf "${Red}No buckets found${Reset}\n"; return 1; }

    local choice
    choice=$(pick_from_list buckets "Select S3 Bucket" 1) || return 1

    if [[ "$choice" == "[type manually]" ]]; then
        read -rp "S3 bucket: " choice
    fi
    [[ -z "$choice" ]] && return 1
    BUCKET="$choice"
}

###############################################################################
# Browse folders (prefixes) within current bucket/prefix, one level at a time
###############################################################################
browse_prefix() {
    local current="${1:-}"

    while true
    do
        printf "${Yellow}Listing s3://%s/%s ...${Reset}\n" "$BUCKET" "$current"
        local out
        out=$(run aws --cli-connect-timeout 10 --cli-read-timeout 20 s3 ls "s3://${BUCKET}/${current}" --profile "$AWS_PROFILE_NAME") || {
            printf "${Red}Unable to list prefix:${Reset}\n%s\n" "$out"
            return 1
        }

        local -a folders
        mapfile -t folders < <(printf "%s\n" "$out" | awk '/PRE / {print $2}')

        local -a menu=("[use this folder: /${current}]" "${folders[@]}")
        local choice
        choice=$(pick_from_list menu "Browse Folder: /${current}" 1) || return 1

        case "$choice" in
            "[use this folder: /${current}]")
                PREFIX="$current"
                return 0
                ;;
            "[type manually]")
                read -rp "S3 prefix/folder: " choice
                [[ -n "$choice" ]] && { PREFIX="$choice"; return 0; }
                ;;
            *)
                current="${current}${choice}"
                ;;
        esac
    done
}

###############################################################################
# Prompts
###############################################################################
prompt_config() {
    printf "${Bold}${Cyan}"
    printf "┌────────────────────────────────────────────────────────────┐\n"
    center_box_line "S3 Asset Downloader" 60
    printf "└────────────────────────────────────────────────────────────┘\n"
    printf "${Reset}\n"

    # PROFILE
    if (( HAVE_CFG_PROFILE )); then
        AWS_PROFILE_NAME="$CFG_PROFILE"
        printf "AWS profile: %s ${Cyan}(from config)${Reset}\n" "$AWS_PROFILE_NAME"
    else
        input=""
        local default_profile="${AWS_PROFILE:-default}"
        if [[ "${YES}" =~ Y ]]; then
            input="${AWS_PROFILE_NAME:-$default_profile}"
        else
            read -rp "AWS profile [${AWS_PROFILE_NAME:-$default_profile}]: " input
        fi
        AWS_PROFILE_NAME="${input:-${AWS_PROFILE_NAME:-$default_profile}}"
        [[ "$AWS_PROFILE_NAME" == "default" ]] && AWS_PROFILE_NAME="${AWS_PROFILE:-default}"
    fi

    # BUCKET
    if (( HAVE_CFG_BUCKET )); then
        BUCKET="$CFG_BUCKET"
        printf "S3 bucket: %s ${Cyan}(from config)${Reset}\n" "$BUCKET"
    elif [[ -z "$BUCKET" || "$BUCKET" == "default" ]]; then
        browse_bucket || { printf "${Red}Bucket selection cancelled${Reset}\n"; exit 1; }
    else
        input=""
        if [[ "${YES}" =~ Y ]]; then
            input="${BUCKET}"
        else
            read -rp "S3 bucket [${BUCKET}] (blank=keep, 'browse'=pick): " input
        fi
        if [[ "$input" == "browse" ]]; then
            browse_bucket || { printf "${Red}Bucket selection cancelled${Reset}\n"; exit 1; }
        elif [[ -n "$input" ]]; then
            BUCKET="$input"
        fi
    fi

    # PREFIX
    if (( HAVE_CFG_PREFIX )); then
        PREFIX="$CFG_PREFIX"
        printf "S3 prefix: %s ${Cyan}(from config)${Reset}\n" "${PREFIX:-<bucket root>}"
    elif [[ -z "$PREFIX" || "$PREFIX" == "default" ]]; then
        browse_prefix "" || { printf "${Red}Prefix selection cancelled${Reset}\n"; exit 1; }
    else
        input=""
        if [[ "${YES}" =~ Y ]]; then
            input="${PREFIX}"
        else
            read -rp "S3 prefix/folder [${PREFIX}] (blank=keep, 'browse'=pick): " input
        fi
        if [[ "$input" == "browse" ]]; then
            browse_prefix "$PREFIX" || { printf "${Red}Prefix selection cancelled${Reset}\n"; exit 1; }
        elif [[ -n "$input" ]]; then
            PREFIX="$input"
        fi
    fi
    [[ "$PREFIX" == */ || -z "$PREFIX" ]] || PREFIX="${PREFIX}/"




    # DEST_DIR
    if (( HAVE_CFG_DEST_DIR )); then
        DEST_DIR="$CFG_DEST_DIR"
        printf "S3 destination dir: %s ${Cyan}(from config)${Reset}\n" "$DEST_DIR"
    else
        input=""
        if [[ "${YES}" =~ Y ]]; then
            input="${DEST_DIR:-./${PREFIX%/}}"
        else
            read -rp "Destination directory [${DEST_DIR:-./${PREFIX%/}}]: " input
        fi
        DEST_DIR="${input:-${DEST_DIR:-./${PREFIX%/}}}"
    fi





    printf "\n"
}

###############################################################################
# AWS validation
###############################################################################
validate_aws_auth() {
    printf "${Yellow}Checking AWS authentication (profile: %s)...${Reset}\n" "$AWS_PROFILE_NAME"

    local out
    if ! out=$(run aws --cli-connect-timeout 10 --cli-read-timeout 20 sts get-caller-identity --profile "$AWS_PROFILE_NAME")
    then
        printf "\n${Red}${Cross} AWS CLI is not authenticated:${Reset}\n%s\n" "$out"
        printf "Log: %s\n" "$LOGFILE"
        return 1
    fi

    printf "${Green}${Tick} AWS Authentication OK${Reset}\n\n"
}

###############################################################################
# List objects
###############################################################################
list_objects() {
    local s3_uri="s3://${BUCKET}/${PREFIX}"
    local list

    printf "${Yellow}Retrieving object list from %s...${Reset}\n" "$s3_uri"

    if ! list=$(run aws --cli-connect-timeout 10 --cli-read-timeout 20 s3 ls "$s3_uri" --recursive --profile "$AWS_PROFILE_NAME")
    then
        printf "${Red}Unable to list bucket:${Reset}\n%s\n" "$list"
        return 1
    fi

    mapfile -t FILES < <(printf "%s\n" "$list" | awk '{$1=$2=$3=""; sub(/^ +/,""); print}')

    if (( ${#FILES[@]} == 0 ))
    then
        printf "${Red}No files found.${Reset}\n"
        return 1
    fi
}

###############################################################################
# Non-interactive selection: used when Objects was supplied via config,
# instead of the interactive checkbox menu.
###############################################################################
apply_object_selection_from_config() {
    local i obj want found any=0

    for ((i=0;i<${#FILES[@]};i++)); do SELECTED[i]=0; done

    for obj in "${CFG_OBJECTS[@]}"; do
        want="${PREFIX}${obj}"
        found=0
        for ((i=0;i<${#FILES[@]};i++)); do
            if [[ "${FILES[i]}" == "$want" ]]; then
                SELECTED[i]=1
                found=1
                any=1
                break
            fi
        done
        (( found )) || printf "${Yellow}Warning: object not found, skipping: %s${Reset}\n" "$want"
    done

    if (( ! any )); then
        printf "${Red}None of the requested Objects were found under s3://%s/%s${Reset}\n" "$BUCKET" "$PREFIX"
        return 1
    fi

    local n=0
    for ((i=0;i<${#FILES[@]};i++)); do (( SELECTED[i] )) && ((n++)); done
    printf "${Cyan}Selected %d object(s) from config.${Reset}\n\n" "$n"
    return 0
}

###############################################################################
# Checkbox menu
###############################################################################
select_objects() {
    local count=${#FILES[@]}
    local cursor=0
    local i key

    for ((i=0;i<count;i++)); do SELECTED[$i]=0; done

    printf "${Hide}"
    flush_input

    while true
    do
        printf "${Clear}${Home}"
        printf "${Bold}${Cyan}S3 Asset Downloader${Reset}\n\n"
        printf "Use:\n  ↑ ↓  Move\n  SPACE Toggle\n  a     Select All\n  n     None\n  ENTER Download\n  q     Quit\n\n"

        for ((i=0;i<count;i++))
        do
            if (( cursor==i )); then printf "${Blue}> ${Reset}"; else printf "  "; fi
            if (( SELECTED[i] )); then printf "${Green}${Checked}${Reset} "; else printf "${White}${Box}${Reset} "; fi
            printf "%s\n" "${FILES[i]}"
        done

        IFS= read -rsn1 key

        case "$key" in
            "") break ;;
            " ")
                if (( SELECTED[cursor] )); then SELECTED[cursor]=0; else SELECTED[cursor]=1; fi
                ;;
            a) for ((i=0;i<count;i++)); do SELECTED[i]=1; done ;;
            n) for ((i=0;i<count;i++)); do SELECTED[i]=0; done ;;
            q) printf "\nCancelled\n"; printf "${Show}"; return 1 ;;
            $'\x1b')
                read -rsn2 key
                case "$key" in
                    "[A") ((cursor--)) ;;
                    "[B") ((cursor++)) ;;
                esac
                ((cursor<0)) && cursor=0
                ((cursor>=count)) && cursor=$((count-1))
                ;;
        esac
    done

    printf "${Show}"
}

###############################################################################
# Download
###############################################################################
download_selected() {
    printf "${Clear}${Home}"
    printf "${Bold}${Green}Downloading selected assets...${Reset}\n\n"

    local downloaded=0 failed=0 i file

    mkdir -p "$DEST_DIR"

    for ((i=0;i<${#FILES[@]};i++))
    do
        (( SELECTED[i] )) || continue
        file="${FILES[i]}"

        printf "${Yellow}Downloading %s...${Reset}\n" "$file"

        if run aws --cli-connect-timeout 10 --cli-read-timeout 60 s3 cp "s3://${BUCKET}/${file}" "${DEST_DIR}/$(basename "$file")" --profile "$AWS_PROFILE_NAME"
        then
            ((downloaded++))
            printf "${Green}${Tick}${Reset}\n"
        else
            ((failed++))
            printf "${Red}${Cross}${Reset}\n"
        fi
        printf "\n"
    done

    print_summary "$downloaded" "$failed"
}

# Prints one "│  centered text  │" row, computing left/right padding from the
# given interior width so the right border always lands in the same column
# as the top/bottom border - regardless of the text's length. (The banner's
# previous version hand-typed the padding spaces, and they didn't add up to
# the same interior width as the border line, which is why the right edge
# was consistently a couple of columns short.)
center_box_line() {
    local text=$1 width=$2
    local pad_left=$(( (width - ${#text}) / 2 ))
    local pad_right=$(( width - ${#text} - pad_left ))
    (( pad_left < 0 )) && pad_left=0
    (( pad_right < 0 )) && pad_right=0
    printf "│%*s%s%*s│\n" "$pad_left" "" "$text" "$pad_right" ""
}

# Prints one "│ label : value│" row, padded so the right border always lands
# in the same column regardless of label/value length. (The previous version
# hand-typed a different number of spaces per label - "Downloaded : " vs
# "Failed      : " vs "Duration    : " - which is why the box edges drifted.)
summary_row() {
    local label=$1 value=$2
    printf "│%-53s│\n" " ${label} : ${value}"
}

print_summary() {
    local downloaded=$1 failed=$2
    local end elapsed
    end=$(date +%s)
    elapsed=$((end-START_TIME))

    printf "\n${Bold}${Cyan}"
    printf "┌─────────────────────────────────────────────────────┐\n"
    printf "│                     Summary                         │\n"
    printf "├─────────────────────────────────────────────────────┤\n"
    summary_row "Downloaded" "$downloaded"
    summary_row "Failed" "$failed"
    summary_row "Duration" "${elapsed}s"
    printf "└─────────────────────────────────────────────────────┘\n"
    printf "${Reset}\n"

    printf "${Green}Log file:${Reset}\n  %s\n\n" "$LOGFILE"
}

###############################################################################
# Main
###############################################################################
main() {
    require_jq
    parse_cli_args "$@"
    apply_cli_config

    load_mru
    prompt_config

    validate_aws_auth || exit 1
    list_objects || exit 1

    if (( HAVE_CFG_OBJECTS )); then
        apply_object_selection_from_config || exit 1
    else
        select_objects || { save_mru; exit 0; }
    fi

    download_selected
    save_mru
}

main "$@"
