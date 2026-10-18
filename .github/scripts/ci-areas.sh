#!/usr/bin/env bash
# Reads changed file paths on stdin, one per line, and prints which CI jobs
# must run as GitHub output lines: "ios=true|false" and "deno=true|false".
# A change under .github/ runs every job, since it can change any of them.
set -euo pipefail

ios=false
deno=false
while IFS= read -r path || [[ -n "$path" ]]; do
  case "$path" in
    .github/*)
      ios=true; deno=true ;;
    PokerStats/*|PokerStatsWidgets/*|PokerStatsTests/*|PokerStatsUITests/*|PokerStats.xcodeproj/*|project.yml|ci_scripts/*|fastlane/*)
      ios=true ;;
    supabase/*)
      deno=true ;;
  esac
done

echo "ios=$ios"
echo "deno=$deno"
