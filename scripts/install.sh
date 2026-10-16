#!/bin/bash
# Builds the app, installs it to ~/Applications and starts it. Run again to update.
set -euo pipefail
cd "$(dirname "$0")/.."

command -v gh >/dev/null || echo "Note: the GitHub CLI is not installed. Install it with: brew install gh"
scripts/build-app.sh
DEST="$HOME/Applications/Review Queue.app"
pkill -x ReviewQueue 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST" && cp -R "dist/Review Queue.app" "$DEST"
open "$DEST"
echo "Installed $DEST. Look for the pull-request icon in the menu bar."
