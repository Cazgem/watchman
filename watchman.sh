#!/bin/bash

# Nightly auto-commit script using a reusable function.

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
MSG="Nightly auto-commit on $TIMESTAMP"

########################################
# Reusable function
########################################
scan_and_commit() {
    local PATH_GLOB="$1"
    local LABEL="$2"

    echo "=== Checking $LABEL ==="

    for REPO in $PATH_GLOB; do
        echo "Checking $REPO"

        # Skip if not a git repo
        if [[ ! -d "$REPO/.git" ]]; then
            echo "Skipping $REPO (not a git repo)"
            echo "----"
            continue
        fi

        cd "$REPO" || continue

        git pull --rebase

        if [[ -n "$(git status --porcelain)" ]]; then
            echo "Changes found — committing..."
            git add -A
            git commit -m "$MSG"
            git push
        else
            echo "No changes in $REPO"
        fi

        echo "----"
    done
}

########################################
# Hard-coded repos
########################################
HARDCODED_REPOS=(
    "/home/zach/projects/mjolnir"
    "/srv/heimdall"
)

scan_hardcoded() {
    echo "=== Checking hard-coded repositories ==="

    for REPO in "${HARDCODED_REPOS[@]}"; do
        echo "Checking $REPO"

        if [[ ! -d "$REPO/.git" ]]; then
            echo "Skipping $REPO (not a git repo)"
            echo "----"
            continue
        fi

        cd "$REPO" || continue

        git pull --rebase

        if [[ -n "$(git status --porcelain)" ]]; then
            echo "Changes found — committing..."
            git add -A
            git commit -m "$MSG"
            git push
        else
            echo "No changes in $REPO"
        fi

        echo "----"
    done
}

########################################
# Calls
########################################

scan_and_commit "/srv/www/*/html" "web directories"
# scan_and_commit "/srv/projects/*" "project directories"
scan_hardcoded
