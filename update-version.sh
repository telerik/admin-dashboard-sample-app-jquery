#!/usr/bin/env bash
set -euo pipefail

LATEST_RELEASE=$(curl -fsSL https://api.github.com/repos/telerik/kendo-ui-core/releases | jq -er '[.[] | select(.prerelease == false)][0].tag_name | sub("^v"; "")')
LATEST_THEMES_RELEASE=$(curl -fsSL https://api.github.com/repos/telerik/kendo-themes/releases | jq -er '[.[] | select(.prerelease == false)][0].tag_name | sub("^v"; "")')
echo "Last Kendo release version is $LATEST_RELEASE"
echo "Last Themes release version is $LATEST_THEMES_RELEASE"

node .github/workflows/update-kendo-assets.js "$LATEST_RELEASE" "$LATEST_THEMES_RELEASE"