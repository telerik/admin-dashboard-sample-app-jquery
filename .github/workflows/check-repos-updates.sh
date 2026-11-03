#!/usr/bin/env bash
set -euo pipefail

echo "Stage1 Find Updates"
KENDO_VERSION="${2:-}"
THEMES_VERSION="${3:-}"
if [[ -z "$KENDO_VERSION" && -z "$THEMES_VERSION" ]]; then
    KENDO_VERSION=$(curl -fsSL https://api.github.com/repos/telerik/kendo-ui-core/releases | jq -er '[.[] | select(.prerelease == false)][0].tag_name | sub("^v"; "")')
    THEMES_VERSION=$(curl -fsSL https://api.github.com/repos/telerik/kendo-themes/releases | jq -er '[.[] | select(.prerelease == false)][0].tag_name | sub("^v"; "")')
elif [[ -z "$KENDO_VERSION" || -z "$THEMES_VERSION" ]]; then
    echo "Provide both Kendo and themes versions, or leave both blank to use the latest stable releases." >&2
    exit 1
fi
LATEST_RELEASE="$KENDO_VERSION"
LATEST_THEMES_RELEASE="$THEMES_VERSION"
echo "Selected Kendo version is $LATEST_RELEASE"
echo "Selected themes version is $LATEST_THEMES_RELEASE"

node .github/workflows/update-kendo-assets.js "$LATEST_RELEASE" "$LATEST_THEMES_RELEASE"

echo "Stage2 Commit the change"
DATE=${DATE:-$(date +%F)}
reviewers="Dimitar-Goshev"
echo $reviewers
BRANCH_NAME="update-dependencies"
PRs=$(gh pr list | grep "$BRANCH_NAME" || true)
echo "PRs are:"
echo $PRs
echo "Branch is:"
echo $BRANCH_NAME
if [ ! -z $PRs ]; then
    echo "Unmerged pr $BRANCH_NAME"
else
    git fetch origin
    git pull
    git checkout -b $BRANCH_NAME
    git config user.email "kendo-bot@progress.com"
    git config user.name "kendo-bot"
    git add . && git commit -m "chore: update dependencies"
    git pull
    git push -u origin $BRANCH_NAME
    gh pr create --base master --head $BRANCH_NAME --reviewer $reviewers \
    --title "Update dependencies $DATE" --body 'Please review and update dependencies'

    git diff
fi