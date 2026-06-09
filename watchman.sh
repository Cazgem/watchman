#!/bin/bash
#
# ============================================================
#  Watchman v1.0.0
#  Automated Git Maintenance, Commit, Rebase, and Tagging
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
# ============================================================

LOGFILE="/var/log/nightly-commit-$(date '+%Y-%m-%d').log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
MSG="Nightly auto-commit on $TIMESTAMP"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOGFILE"
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
# Reusable function
########################################
scan_and_commit() {
    local PATH_GLOB="$1"
    local LABEL="$2"

    log "=== Checking $LABEL ==="

    for REPO in $PATH_GLOB; do
        log "--- Repo: $REPO ---"

        if [[ ! -d "$REPO/.git" ]]; then
            log "Skipping (not a git repo)"
            continue
        fi

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
        git.fetch origin "$PRIMARY_BRANCH" &>/dev/null

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
# Calls
########################################

scan_and_commit "/srv/www/*/html" "web directories"
scan_and_commit "/srv/projects/*" "project directories"
scan_hardcoded

log "=== Nightly commit complete ==="
