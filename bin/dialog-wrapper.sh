#!/usr/bin/env bash
: <<DOCXX

----
create a bash wrapper script for the creation of reusable and portable user input menus using the dialog command that does the following:
1) checks that dialog and any other required commands are available or prompts for confirmation to install the command if the command is not installed, or provides a PATH fix if the command is installed but not in the PATH environmental variable (if -y, --yes flag is supplied on the command line then install the command(s) before continuing
2) specification of PROMPT phrase
3) prompts user for input items to be selected using either 
  3a) single key press with no ENTER key press required
  3b) numbered item selection with the optional capability of selecting multiple items 
  3c) exact cap sensitive phrase required  
4) specify TIMEOUT in seconds
5) capability to define a default value to be used if TIMEOUT reached or ENTER pressed
6) select dialog types :calendar, checklist, dselect, editbox, form, fselect, gauge, infobox, inputbox, inputmenu, menu, mixedform, mixedgauge, msgbox (message), passwordbox, passwordform, pause, progressbox, radiolist, tailbox, tailboxbg, textbox, timebox, and yesno (yes/no)
7) store configuration as JSON or YAML that this script can use to create required dialog command snippets or complete scripts
----

Author: morgan@morganism.dev
Date: Mon 11 May 2026 23:06:56 BST
DOCXX
#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.1"

AUTO_YES=0
CONFIG_FILE=""
MODE="run"

die() { echo "ERROR: $*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

prompt_yes_no() {
  local msg="$1"
  [[ $AUTO_YES -eq 1 ]] && return 0
  read -rp "$msg [y/N]: " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

# -------------------------------
# Package install (Linux + macOS)
# -------------------------------
install_pkg() {
  local pkg="$1"

  if have brew; then
    brew install "$pkg"
  elif have apt-get; then
    sudo apt-get update && sudo apt-get install -y "$pkg"
  elif have dnf; then
    sudo dnf install -y "$pkg"
  elif have yum; then
    sudo yum install -y "$pkg"
  elif have pacman; then
    sudo pacman -Sy --noconfirm "$pkg"
  else
    die "No supported package manager found (install $pkg manually)"
  fi
}

ensure_cmd() {
  local cmd="$1"
  local pkg="$2"

  if have "$cmd"; then
    return
  fi

  echo "Missing command: $cmd"

  if prompt_yes_no "Install package '$pkg'?"; then
    install_pkg "$pkg"
  else
    die "Required command '$cmd' not installed"
  fi
}

# -------------------------------
# Args
# -------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -c|--config) CONFIG_FILE="$2"; shift 2 ;;
    -y|--yes) AUTO_YES=1; shift ;;
    --generate) MODE="generate"; shift ;;
    -h|--help)
      echo "Usage: $0 -c config.{json|yaml} [-y] [--generate]"
      exit 0 ;;
    *) die "Unknown argument: $1" ;;
  esac
done

[[ -n "$CONFIG_FILE" ]] || die "Config file required (-c)"

# -------------------------------
# Dependencies
# -------------------------------
ensure_cmd dialog dialog
ensure_cmd jq jq

if [[ "$CONFIG_FILE" =~ \.ya?ml$ ]]; then
  ensure_cmd yq yq
fi

# -------------------------------
# Config loader
# -------------------------------
load_cfg() {
  local key="$1"
  if [[ "$CONFIG_FILE" =~ \.json$ ]]; then
    jq -r "$key" "$CONFIG_FILE"
  else
    yq eval -r "$key" "$CONFIG_FILE"
  fi
}

PROMPT=$(load_cfg '.prompt')
TYPE=$(load_cfg '.type')
TIMEOUT=$(load_cfg '.timeout // 0')
DEFAULT=$(load_cfg '.default // ""')
HEIGHT=$(load_cfg '.height // 15')
WIDTH=$(load_cfg '.width // 60')

# -------------------------------
# Dialog build
# -------------------------------
DIALOG_CMD=(dialog --clear)

[[ "$TIMEOUT" -gt 0 ]] && DIALOG_CMD+=(--timeout "$TIMEOUT")

case "$TYPE" in
  yesno)
    DIALOG_CMD+=(--yesno "$PROMPT" "$HEIGHT" "$WIDTH")
    ;;
  msgbox)
    DIALOG_CMD+=(--msgbox "$PROMPT" "$HEIGHT" "$WIDTH")
    ;;
  inputbox)
    DIALOG_CMD+=(--inputbox "$PROMPT" "$HEIGHT" "$WIDTH" "$DEFAULT")
    ;;
  passwordbox)
    DIALOG_CMD+=(--passwordbox "$PROMPT" "$HEIGHT" "$WIDTH")
    ;;
  menu|radiolist|checklist)
    ITEMS=()
    mapfile -t raw_items < <(load_cfg '.items[] | @tsv')
    for row in "${raw_items[@]}"; do
      IFS=$'\t' read -r tag label status <<<"$row"
      ITEMS+=("$tag" "$label" "${status:-off}")
    done
    DIALOG_CMD+=(--"$TYPE" "$PROMPT" "$HEIGHT" "$WIDTH" 10 "${ITEMS[@]}")
    ;;
  calendar|timebox)
    DIALOG_CMD+=(--"$TYPE" "$PROMPT" "$HEIGHT" "$WIDTH")
    ;;
  *)
    die "Unsupported dialog type: $TYPE"
    ;;
esac

# -------------------------------
# Execute or generate
# -------------------------------
if [[ "$MODE" == "generate" ]]; then
  printf '%q ' "${DIALOG_CMD[@]}"
  echo
  exit 0
fi

exec 3>&1
RESULT=$("${DIALOG_CMD[@]}" 2>&1 1>&3 || true)
exec 3>&-

[[ -z "$RESULT" && -n "$DEFAULT" ]] && RESULT="$DEFAULT"

clear
echo "$RESULT"
