#!/usr/bin/env bash
# Tests for ci-areas.sh. Run: .github/scripts/ci-areas-test.sh
set -euo pipefail

script="$(dirname "$0")/ci-areas.sh"
failures=0

expect() {
  local name="$1" want="$2" input="$3" got
  got=$(printf '%s' "$input" | "$script" | paste -sd' ' -)
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want '$want', got '$got'"
    failures=$((failures + 1))
  fi
}

expect "no files"            "ios=false deno=false" ""
expect "docs only"           "ios=false deno=false" $'docs/specs/a.md\nREADME.md\nPRIVACY.md'
expect "app source"          "ios=true deno=false"  "PokerStats/Views/Home.swift"
expect "widgets"             "ios=true deno=false"  "PokerStatsWidgets/Info.plist"
expect "unit tests"          "ios=true deno=false"  "PokerStatsTests/FooTests.swift"
expect "ui tests"            "ios=true deno=false"  "PokerStatsUITests/Snap.swift"
expect "shared scheme"       "ios=true deno=false"  "PokerStats.xcodeproj/xcshareddata/xcschemes/PokerStats.xcscheme"
expect "project.yml"         "ios=true deno=false"  "project.yml"
expect "ci_scripts"          "ios=true deno=false"  "ci_scripts/build_number.sh"
expect "fastlane"            "ios=true deno=false"  "fastlane/Fastfile"
expect "supabase"            "ios=false deno=true"  "supabase/functions/delete-account/index.ts"
expect "migration"           "ios=false deno=true"  "supabase/migrations/0001_init.sql"
expect "both areas"          "ios=true deno=true"   $'supabase/config.toml\nPokerStats/App.swift'
expect "workflow change"     "ios=true deno=true"   ".github/workflows/ci.yml"
expect "prefix lookalike"    "ios=false deno=false" $'PokerStatsDocs/x.md\nproject.yml.bak\nsupabase.md'
expect "no trailing newline" "ios=false deno=true"  "supabase/x.ts"

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
