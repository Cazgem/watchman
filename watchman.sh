#!/bin/bash
#
# ============================================================
#  Watchman v1.0.0
#  Automated Git Stewardship System
#  https://github.com/Cazgem/watchman
#
#  Features:
#   - Clean logging
#   - Primary branch detection (main → master → create main)
#   - Automatic dev-branch creation
#   - Automatic dev → primary rebase
#   - Automatic tagging when dev is merged
#   - Stale rebase cleanup
#   - Hard-coded repo support
#   - WebUI JSON generation
#   - CLI: status, doctor, init, -r /repo
# ============================================================

LOGFILE="/var/log/nightly-commit-$(date '+%Y-%m-%d').log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
MSG="Nightly auto-commit on $TIMESTAMP"
WEBUI_DIR="/srv/www/watchman/api"

resolve_gitdir_path() {
    local REPO_PATH="$1"
    local GIT_DIR_PATH=""

    if [[ -f "$REPO_PATH/.git" ]]; then
        GIT_DIR_PATH="$(sed -n 's/^gitdir: //p' "$REPO_PATH/.git" 2>/dev/null | head -n 1)"
    elif [[ -d "$REPO_PATH/.git" ]]; then
        GIT_DIR_PATH="$REPO_PATH/.git"
    fi

    if [[ -n "$GIT_DIR_PATH" && "$GIT_DIR_PATH" != /* ]]; then
        GIT_DIR_PATH="$REPO_PATH/$GIT_DIR_PATH"
    fi

    if [[ -n "$GIT_DIR_PATH" ]]; then
        GIT_DIR_PATH="$(readlink -f "$GIT_DIR_PATH" 2>/dev/null || printf '%s' "$GIT_DIR_PATH")"
    fi

    printf '%s\n' "$GIT_DIR_PATH"
}

ASCII_LOGO="

             Watchman — Automated Git Steward
"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOGFILE" >&2
}

ensure_safe_directory() {
    local REPO_PATH="$1"
    local GIT_DIR_PATH=""

    if [[ -f "$REPO_PATH/.git" ]]; then
        GIT_DIR_PATH="$(sed -n 's/^gitdir: //p' "$REPO_PATH/.git" 2>/dev/null | head -n 1)"
        if [[ -n "$GIT_DIR_PATH" && "$GIT_DIR_PATH" != /* ]]; then
            GIT_DIR_PATH="$REPO_PATH/$GIT_DIR_PATH"
        fi
        if [[ -n "$GIT_DIR_PATH" ]]; then
            GIT_DIR_PATH="$(readlink -f "$GIT_DIR_PATH" 2>/dev/null || printf '%s' "$GIT_DIR_PATH")"
        fi
    fi

    if git -C "$REPO_PATH" rev-parse --git-dir >/dev/null 2>&1; then
        return 0
    fi

    if git -C "$REPO_PATH" rev-parse --git-dir 2>&1 | grep -q "dubious ownership"; then
        git config --global --add safe.directory "$REPO_PATH" >/dev/null 2>&1
        if [[ -n "$GIT_DIR_PATH" ]]; then
            git config --global --add safe.directory "$GIT_DIR_PATH" >/dev/null 2>&1
        fi
    fi
}

########################################
# Determine primary branch (main/master)
########################################
get_primary_branch() {
    if git show-ref --verify --quiet refs/heads/main; then
        echo "main"
    elif git show-ref --verify --quiet refs/heads/master; then
        echo "master"
    else
        log "No main or master branch found — creating main"
        git checkout -b main &>/dev/null
        git push -u origin main &>/dev/null
        echo "main"
    fi
}

########################################
# Core scanning + commit + rebase logic
########################################
scan_and_commit() {
    local PATH_GLOB="$1"
    local LABEL="$2"
    local GIT_DIR_PATH=""

    log "=== Checking $LABEL ==="

    for REPO in $PATH_GLOB; do
        log "--- Repo: $REPO ---"

        if [[ ! -d "$REPO/.git" ]]; then
            log "Skipping (not a git repo)"
            continue
        fi

        GIT_DIR_PATH="$(resolve_gitdir_path "$REPO")"
        if [[ "$GIT_DIR_PATH" == *"/releases/"* ]]; then
            log "Skipping (backed by release folder: $GIT_DIR_PATH)"
            continue
        fi

        ensure_safe_directory "$REPO"

        cd "$REPO" || continue

        # Clean stale rebase state
        if [[ -d ".git/rebase-apply" || -d ".git/rebase-merge" ]]; then
            log "Stale rebase detected — cleaning"
            git rebase --abort 2>/dev/null
            rm -rf .git/rebase-apply .git/rebase-merge
        fi

        ########################################
        # Primary branch + dev branch
        ########################################
        PRIMARY_BRANCH=$(get_primary_branch)

        if ! git show-ref --verify --quiet refs/heads/dev; then
            log "No dev branch — creating dev from $PRIMARY_BRANCH"
            git checkout "$PRIMARY_BRANCH" &>/dev/null
            git pull &>/dev/null
            git checkout -b dev &>/dev/null
            git push -u origin dev &>/dev/null
        fi

        git checkout dev &>/dev/null
        git pull --rebase &>/dev/null

        ########################################
        # Auto-rebase dev onto primary branch
        ########################################
        log "Rebasing dev onto $PRIMARY_BRANCH"
        git fetch origin "$PRIMARY_BRANCH" &>/dev/null

        if git rebase "origin/$PRIMARY_BRANCH" &>/dev/null; then
            log "Rebase successful"
            git push --force-with-lease &>/dev/null
            log "Pushed rebased dev"
        else
            log "Rebase conflict — aborting and skipping repo"
            git rebase --abort &>/dev/null
            continue
        fi

        ########################################
        # Commit if needed
        ########################################
        if [[ -n "$(git status --porcelain)" ]]; then
            log "Changes found — committing"
            git add -A
            git commit -m "$MSG" &>/dev/null
            git push &>/dev/null
            log "Pushed dev"
        else
            log "No changes"
        fi

        ########################################
        # Merge readiness + auto-tagging
        ########################################
        git fetch origin "$PRIMARY_BRANCH" &>/dev/null

        AHEAD_BEHIND=$(git rev-list --left-right --count "origin/$PRIMARY_BRANCH"...dev)
        MAIN_BEHIND=$(echo "$AHEAD_BEHIND" | awk '{print $1}')
        DEV_AHEAD=$(echo "$AHEAD_BEHIND" | awk '{print $2}')

        if [[ "$DEV_AHEAD" -gt 0 ]]; then
            log "⚠ dev is ahead of $PRIMARY_BRANCH by $DEV_AHEAD commits — merge review needed"
        else
            if [[ "$MAIN_BEHIND" -gt 0 ]]; then
                log "✔ dev has been merged into $PRIMARY_BRANCH — tagging release"

                git checkout "$PRIMARY_BRANCH" &>/dev/null
                git pull &>/dev/null

                TAG="release-$(date '+%Y-%m-%d_%H-%M-%S')"
                git tag -a "$TAG" -m "Auto-tag after dev merge" &>/dev/null
                git push origin "$TAG" &>/dev/null

                log "Created and pushed tag: $TAG"

                git checkout dev &>/dev/null
            else
                log "dev and $PRIMARY_BRANCH are identical — no tag needed"
            fi
        fi

        log ""
    done
}

########################################
# Hard-coded repos
########################################
HARDCODED_REPOS=(
    "/home/zach/scripts/mytool"
    "/srv/misc/special-repo"
    "/opt/internal/automation"
)

scan_hardcoded() {
    log "=== Checking hard-coded repositories ==="

    for REPO in "${HARDCODED_REPOS[@]}"; do
        log "--- Repo: $REPO ---"

        if [[ ! -d "$REPO/.git" ]]; then
            log "Skipping (not a git repo)"
            continue
        fi

        GIT_DIR_PATH="$(resolve_gitdir_path "$REPO")"
        if [[ "$GIT_DIR_PATH" == *"/releases/"* ]]; then
            log "Skipping (backed by release folder: $GIT_DIR_PATH)"
            continue
        fi

        ensure_safe_directory "$REPO"

        cd "$REPO" || continue

        PRIMARY_BRANCH=$(get_primary_branch)

        if ! git show-ref --verify --quiet refs/heads/dev; then
            log "No dev branch — creating dev from $PRIMARY_BRANCH"
            git checkout "$PRIMARY_BRANCH" &>/dev/null
            git pull &>/dev/null
            git checkout -b dev &>/dev/null
            git push -u origin dev &>/dev/null
        fi

        git checkout dev &>/dev/null
        git pull --rebase &>/dev/null

        if [[ -n "$(git status --porcelain)" ]]; then
            log "Changes found — committing"
            git add -A
            git commit -m "$MSG" &>/dev/null
            git push &>/dev/null
            log "Pushed dev"
        else
            log "No changes"
        fi

        log ""
    done
}

########################################
# WebUI JSON generation
########################################
generate_webui_json() {
    mkdir -p "$WEBUI_DIR"

    cat > "$WEBUI_DIR/status.json" <<EOF
{
  "timestamp": "$TIMESTAMP",
  "logfile": "$LOGFILE"
}
EOF

    printf "{\n  \"repos\": [\n" > "$WEBUI_DIR/repos.json"
    for R in /srv/www/*/html /srv/projects/* "${HARDCODED_REPOS[@]}"; do
        printf "    \"%s\",\n" "$R" >> "$WEBUI_DIR/repos.json"
    done
    sed -i '$ s/,$//' "$WEBUI_DIR/repos.json"
    printf "  ]\n}\n" >> "$WEBUI_DIR/repos.json"
}

########################################
# CLI Dispatcher
########################################

# Single repo mode
if [[ "$1" == "--single" ]]; then
    scan_and_commit "$2" "single repo"
    generate_webui_json
    exit 0
fi

# Status
if [[ "$1" == "status" ]]; then
    echo "$ASCII_LOGO"
    echo "Watchman Status"
    echo "----------------"
    echo "Last run: $TIMESTAMP"
    echo "Log file: $LOGFILE"
    echo "Scan paths:"
    echo "  - /srv/www/*/html"
    echo "  - /srv/projects/*"
    echo "Hard-coded repos:"
    for R in "${HARDCODED_REPOS[@]}"; do echo "  - $R"; done
    exit 0
fi

# Doctor
if [[ "$1" == "doctor" ]]; then
    echo "$ASCII_LOGO"
    echo "Watchman Doctor"
    echo "----------------"
    echo "Git version:"
    git --version
    echo ""
    echo "Network check:"
    ping -c1 github.com >/dev/null 2>&1 && echo "Network OK" || echo "Network issue"
    echo ""
    echo "Log write test:"
    touch /var/log/watchman-test.log && echo "Log write OK" || echo "Cannot write logs"
    exit 0
fi

# Init
if [[ "$1" == "init" ]]; then
    TARGET="$2"
    if [[ -z "$TARGET" ]]; then
        echo "Usage: watchman init /path/to/repo"
        exit 1
    fi

    cd "$TARGET" || { echo "Invalid path"; exit 1; }

    echo "Initializing repository at $TARGET"

    if [[ ! -d ".git" ]]; then
        git init
        echo "Initialized empty Git repository"
    fi

    if git show-ref --verify --quiet refs/heads/main; then
        PRIMARY="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        PRIMARY="master"
    else
        PRIMARY="main"
        git checkout -b main
        echo "Created main branch"
    fi

    if ! git show-ref --verify --quiet refs/heads/dev; then
        git checkout "$PRIMARY"
        git checkout -b dev
        echo "Created dev branch"
    fi

    echo "Watchman initialization complete."
    exit 0
fi

########################################
# Default: full scan
########################################
scan_and_commit "/srv/www/*/html" "web directories"
scan_and_commit "/srv/projects/*" "project directories"
scan_hardcoded
generate_webui_json

log "=== Nightly commit complete ==="
