#!/bin/sh
# Runs xcodegen generate from the repo root and keeps the committed
# Package.resolved (see README "Dependencies"). xcodegen generate can delete
# that file, so it is copied aside and put back. Fails if the file is missing,
# untracked, or differs from the commit, so a build never starts from
# package versions nobody committed. Used by ci_post_clone.sh (Xcode Cloud)
# and the fastlane beta and release lanes. XCODEGEN overrides the binary.
set -e
cd "$(dirname "$0")/.."

RESOLVED="PokerStats.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if [ ! -f "$RESOLVED" ]; then
  echo "error: $RESOLVED is missing" >&2
  exit 1
fi
if ! git ls-files --error-unmatch -- "$RESOLVED" >/dev/null 2>&1; then
  echo "error: $RESOLVED is not committed" >&2
  exit 1
fi
if ! git diff --quiet HEAD -- "$RESOLVED"; then
  echo "error: $RESOLVED differs from the commit. Commit it or run: git restore $RESOLVED" >&2
  exit 1
fi
RESOLVED_BACKUP="$(mktemp)"
trap 'rm -f "$RESOLVED_BACKUP"' EXIT
cp "$RESOLVED" "$RESOLVED_BACKUP"

"${XCODEGEN:-xcodegen}" generate

mkdir -p "$(dirname "$RESOLVED")"
cp "$RESOLVED_BACKUP" "$RESOLVED"
