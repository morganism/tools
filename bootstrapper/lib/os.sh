detect_os() {
    case "$(uname -s)" in
        Darwin) OS="macos" ;;
        Linux)  OS="linux" ;;
        *) echo "Unsupported OS"; exit 1 ;;
    esac
}
