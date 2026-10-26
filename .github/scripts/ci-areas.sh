#!/usr/bin/env bash
# Reads changed file paths on stdin, NUL-separated, and prints which CI jobs
# must run as GitHub output lines: "ios=true|false" and "deno=true|false".
# deno covers the edge functions and the sync contract in shared/.
# A change under .github/ runs every job, since it can change any of them.
set -euo pipefail

ios=false
deno=false
while IFS= read -r -d '' path || [[ -n "$path" ]]; do
  case "$path" in
    .github/*)
      ios=true; deno=true ;;
    PokerStats/*|PokerStatsWidgets/*|PokerStatsTests/*|PokerStatsUITests/*|PokerStats.xcodeproj/*|project.yml|ci_scripts/*|fastlane/*)
      ios=true ;;
    supabase/*|shared/*)
      deno=true ;;
  esac
done

echo "ios=$ios"
echo "deno=$deno"
