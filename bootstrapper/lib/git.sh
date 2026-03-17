ensure_git_installed() {
    if ! command -v git >/dev/null; then
        if [ "$OS" = "macos" ]; then
            xcode-select --install
        else
            sudo apt update && sudo apt install -y git
        fi
    fi
}

configure_git_field() {
  local key="$1"
  local label="$2"
  local current value yn confirm

  current="$(git config --global "$key")"

  while true; do
    echo "Current git $label: ${current:-<not set>}"

    if read -t 5 -n 1 -s -rp "Change it? [y/N]: " yn; then
      echo
    else
      echo
      yn="n"
    fi

    case "$yn" in
      [yY])
        while true; do
          read -rp "New git $label: " value
          [ -z "$value" ] && echo "Value cannot be empty." && continue

          if read -n 1 -s -rp "Use '$value'? [y/N]: " confirm; then
            echo
          else
            echo
            confirm="n"
          fi

          [[ "$confirm" =~ ^[yY]$ ]] && break
        done

        git config --global "$key" "$value"
        break
        ;;
      *)
        break
        ;;
    esac
  done
}

configure_git() {

  configure_git_field "user.name" "name"
  configure_git_field "user.email" "email"

  git config --global init.defaultBranch master
  git config --global pull.rebase false
}
