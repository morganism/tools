#!/usr/bin/env bash
: <<DOCXX
Add description
Author: morgan@morganism.dev
Date: Fri 27 Feb 2026 05:35:00 GMT
DOCXX

set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$BOOTSTRAP_DIR/lib"
TASKS="$BOOTSTRAP_DIR/tasks"

source "$LIB/os.sh"
source "$LIB/git.sh"
source "$LIB/github.sh"
source "$LIB/repo.sh"
source "$LIB/update.sh"

run_script() {
    local script="$1"

    if [[ "$script" =~ ^https?:// ]]; then
        echo "Running remote script: $script"
        bash <(curl -fsSL "$script")
    elif [[ -f "$script" ]]; then
        echo "Running local script: $script"
        bash <(cat "$script")
    else
        echo "Script not found: $script"
        return 1
    fi
}

run_all_tasks() {
    [ -d "$TASKS" ] || return

    find "$TASKS" -type f -perm -111 -print0 |
    while IFS= read -r -d '' task; do
        run_script "$task"
    done
}

main() {
    detect_os
    ensure_git_installed
    configure_git
    ensure_gh_installed
    github_auth
    check_for_updates
    run_all_tasks
}

main "$@"
