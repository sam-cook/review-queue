#!/bin/bash
# Installs or updates Review Queue, a macOS menu bar app for GitHub pull requests.
#
#   curl -fsSL https://raw.githubusercontent.com/sam-cook/review-queue/main/install.sh | bash
#
# Options (environment variables):
#   REVIEW_QUEUE_VERSION=1.2.3   install that version instead of the latest
#   REVIEW_QUEUE_DIR=/Applications  install somewhere else (default: ~/Applications)
#   REVIEW_QUEUE_ZIP=<url|path>  install from this zip (for testing)
#
# Uninstall:  curl -fsSL https://raw.githubusercontent.com/sam-cook/review-queue/main/install.sh | bash -s -- --uninstall
set -euo pipefail

REPO="sam-cook/review-queue"
APP_NAME="Review Queue.app"
BUNDLE_ID="io.github.sam-cook.review-queue"
DIR="${REVIEW_QUEUE_DIR:-$HOME/Applications}"
APP="$DIR/$APP_NAME"

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Review Queue runs on macOS only."
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "Review Queue needs macOS 14 (Sonoma) or later; this Mac has $(sw_vers -productVersion)."

if [[ "${1:-}" == "--uninstall" ]]; then
  [[ -x "$APP/Contents/MacOS/ReviewQueue" ]] && "$APP/Contents/MacOS/ReviewQueue" --unregister-login-item || true
  pkill -f "$APP/Contents/MacOS/ReviewQueue" 2>/dev/null || true
  rm -rf "$APP"
  defaults delete "$BUNDLE_ID" 2>/dev/null || true
  say "Removed Review Queue."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
zip="$tmp/ReviewQueue.zip"

if [[ -n "${REVIEW_QUEUE_ZIP:-}" ]]; then
  say "Downloading $REVIEW_QUEUE_ZIP"
  case "$REVIEW_QUEUE_ZIP" in
    http*|file:*) curl -fsSL "$REVIEW_QUEUE_ZIP" -o "$zip" ;;
    *) cp "$REVIEW_QUEUE_ZIP" "$zip" ;;
  esac
else
  tag="${REVIEW_QUEUE_VERSION:+v${REVIEW_QUEUE_VERSION#v}}"
  if [[ -z "$tag" ]]; then
    # The redirect from /releases/latest names the tag; no API call or token needed.
    # Empty when the repository is private or has no release yet; gh below covers the first case.
    tag="$(curl -fsSIL -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null | sed -n 's#.*/tag/##p' || true)"
  fi
  if [[ -n "$tag" ]] && curl -fsSL "https://github.com/$REPO/releases/download/$tag/ReviewQueue-${tag#v}.zip" -o "$zip" 2>/dev/null; then
    say "Downloaded Review Queue ${tag#v}"
  elif command -v gh >/dev/null && gh release download ${tag:+"$tag"} -R "$REPO" -p 'ReviewQueue-*.zip' -O "$zip" 2>/dev/null; then
    # A private repository, or a network that blocks the release URL: gh uses your login.
    say "Downloaded Review Queue ${tag:+${tag#v} }with gh"
  else
    fail "Could not download a release from github.com/$REPO."
  fi
fi

# Quit a running copy, then replace it.
# Only this installation: other builds may share the process name.
if pgrep -f "$APP/Contents/MacOS/ReviewQueue" >/dev/null; then
  say "Quitting the running Review Queue"
  pkill -f "$APP/Contents/MacOS/ReviewQueue" || true
  sleep 1
fi
mkdir -p "$DIR"
ditto -x -k "$zip" "$tmp/unzipped"
[[ -d "$tmp/unzipped/$APP_NAME" ]] || fail "The download did not contain $APP_NAME."
rm -rf "$APP"
mv "$tmp/unzipped/$APP_NAME" "$APP"
# Files fetched with curl are not quarantined; this also covers a zip copied from a browser download.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
say "Installed $APP"

if ! command -v gh >/dev/null && ! [[ -x /opt/homebrew/bin/gh || -x /usr/local/bin/gh ]]; then
  say "Review Queue reads your GitHub login from the GitHub CLI. Install it and log in:"
  echo "      brew install gh && gh auth login"
fi

open "$APP"
say "Started. Look for the pull-request icon in the menu bar."
