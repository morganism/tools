ensure_gh_installed() {
    if ! command -v gh >/dev/null; then
        if [ "$OS" = "macos" ]; then
            brew install gh
        else
            sudo apt install -y gh
        fi
    fi
}

github_auth() {
    if ! gh auth status >/dev/null 2>&1; then
        gh auth login
    fi
}
