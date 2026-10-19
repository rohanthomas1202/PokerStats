#!/bin/sh
set -e

echo "Installing XcodeGen..."
brew install xcodegen

echo "Generating Xcode project from project.yml..."
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Package.resolved is committed (see README "Dependencies"). Keep it across
# xcodegen generate, so packages resolve to the pinned versions.
RESOLVED="PokerStats.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
if [ ! -f "$RESOLVED" ]; then
  echo "error: $RESOLVED is missing" >&2
  exit 1
fi
RESOLVED_BACKUP="$(mktemp)"
cp "$RESOLVED" "$RESOLVED_BACKUP"

xcodegen generate

mkdir -p "$(dirname "$RESOLVED")"
cp "$RESOLVED_BACKUP" "$RESOLVED"
rm -f "$RESOLVED_BACKUP"

echo "Project generated successfully."
