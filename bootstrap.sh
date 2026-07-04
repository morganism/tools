#!/usr/bin/env bash
set -euo pipefail

THIS_PATH() {
    realpath "${BASH_SOURCE[1]}" # return absolute path to the script where THIS_PATH is called from
}
THIS_DIR() {
  dirname "$(THIS_PATH)"
}
THIS_FILE() {
  basename "$(THIS_PATH)"
}


[[ -f ~/.ansi.functions ]] && . ~/.ansi.functions || ( echo -e "🧚 Help on the way" && exit 127 )

call_linker() {
  echo -e "${dWhite}call_linker()${Reset}"
  echo -e "${Grey_8}THIS_DIR [$(THIS_DIR)]${Reset}"
  $(THIS_DIR)/linker
}
call_linker




