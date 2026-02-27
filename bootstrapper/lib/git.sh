ensure_git_installed() {
    if ! command -v git >/dev/null; then
        if [ "$OS" = "macos" ]; then
            xcode-select --install
        else
            sudo apt update && sudo apt install -y git
        fi
    fi
}

configure_git() {
    read -rp "Git user.name: " NAME
    read -rp "Git user.email: " EMAIL

    git config --global user.name "$NAME"
    git config --global user.email "$EMAIL"
    git config --global init.defaultBranch main
    git config --global pull.rebase false
}
