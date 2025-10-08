#!/usr/bin/env bash
echo "Stage1 Find Updates"
LATEST_RELEASE=$(curl -s https://api.github.com/repos/telerik/kendo-ui-core/releases | grep tag_name | head -n 1 |  cut -d '"' -f 4)
# Use the same pattern as LATEST_RELEASE but for themes
LATEST_THEMES_RELEASE=$(curl -s https://api.github.com/repos/telerik/kendo-themes/releases | grep tag_name | head -n 1 | cut -d '"' -f 4 | sed 's/^v//')

echo "Raw LATEST_RELEASE: '$LATEST_RELEASE'"
echo "Raw LATEST_THEMES_RELEASE: '$LATEST_THEMES_RELEASE'"
 
echo "Last release version is $LATEST_RELEASE"
echo "Last Themes release version is $LATEST_THEMES_RELEASE"

function getCurrentVersion {
    for file in `find . -type f -name "*.html"`  
    do
        CURRENT_VERSION=$(grep -hnr "kendo.cdn" "$file" | head -2 | tail -1 | cut -d '/' -f 4)
        if [ ! -z "$CURRENT_VERSION" ]
            then
                CURRENT_GLOBAL_VERSION=$CURRENT_VERSION
                echo "Found current version: $CURRENT_VERSION in file: $file"
                break
        fi
    done
}

function getCurrentThemesVersion {
    for file in `find . -type f -name "*.html"`  
    do
        CURRENT_THEMES_VERSION=$(grep -hnr "kendo.cdn" "$file" | head -1 | cut -d '/' -f 5)
        if [ ! -z "$CURRENT_THEMES_VERSION" ]
            then
                CURRENT_GLOBAL_THEMES_VERSION=$CURRENT_THEMES_VERSION
                echo "Found current themes version: $CURRENT_THEMES_VERSION in file: $file"
                break
        fi
    done
}
    getCurrentVersion
    getCurrentThemesVersion

    echo "Current version is $CURRENT_GLOBAL_VERSION"
    echo "Current themes version is $CURRENT_GLOBAL_THEMES_VERSION"
    echo "Latest version is $LATEST_RELEASE" 
    echo "Latest themes version is $LATEST_THEMES_RELEASE"

# Check if variables are not empty before proceeding
if [ -z "$CURRENT_GLOBAL_VERSION" ] || [ -z "$LATEST_RELEASE" ]; then
    echo "Error: CURRENT_GLOBAL_VERSION or LATEST_RELEASE is empty"
    echo "CURRENT_GLOBAL_VERSION: '$CURRENT_GLOBAL_VERSION'"
    echo "LATEST_RELEASE: '$LATEST_RELEASE'"
    exit 1
fi

if [ -z "$CURRENT_GLOBAL_THEMES_VERSION" ] || [ -z "$LATEST_THEMES_RELEASE" ]; then
    echo "Error: CURRENT_GLOBAL_THEMES_VERSION or LATEST_THEMES_RELEASE is empty"
    echo "CURRENT_GLOBAL_THEMES_VERSION: '$CURRENT_GLOBAL_THEMES_VERSION'"
    echo "LATEST_THEMES_RELEASE: '$LATEST_THEMES_RELEASE'"
    exit 1
fi

echo "Replacing versions in HTML files..."
for file in `find . -type f -name "*.html"`  
do
    echo "Processing file: $file"
    # Use more explicit sed syntax to avoid issues
    sed -i.bak "s|$CURRENT_GLOBAL_VERSION|$LATEST_RELEASE|g" "$file"
    sed -i.bak "s|$CURRENT_GLOBAL_THEMES_VERSION|$LATEST_THEMES_RELEASE|g" "$file"
    # Remove backup files
    rm -f "$file.bak"
done

echo "Stage2 Commit the change"
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

