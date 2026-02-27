check_for_updates() {
    cd "$BOOTSTRAP_DIR"
    git fetch origin main || return
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/main)

    if [ "$LOCAL" != "$REMOTE" ]; then
        echo "Updating bootstrapper..."
        git pull origin main
        exec "$0" "$@"
    fi
}

run_post_bootstrap() {
    if [ -f "$BOOTSTRAP_DIR/tasks/post_bootstrap.sh" ]; then
        bash "$BOOTSTRAP_DIR/tasks/post_bootstrap.sh"
    fi
}
