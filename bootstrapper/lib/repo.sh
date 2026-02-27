create_and_push_repo() {
    read -rp "New repo name: " REPO

    mkdir -p "$REPO"
    cd "$REPO"

    git init
    echo "# $REPO" > README.md
    git add .
    git commit -m "Initial commit"

    gh repo create "$REPO" --private --source=. --remote=origin --push
}
