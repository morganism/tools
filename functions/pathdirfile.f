# return absolute path to the script where THIS_PATH is called from
THIS_PATH() {
    realpath "${BASH_SOURCE[1]}"
}

THIS_DIR() {
    dirname "$(realpath "${BASH_SOURCE[1]}")"
}

THIS_FILE() {
    basename "$(realpath "${BASH_SOURCE[1]}")"
}


