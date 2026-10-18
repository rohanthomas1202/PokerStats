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

# A file moved out of PokerStats/ must still run iOS. Without --no-renames,
# git diff lists only the new path.
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT
git -C "$repo" init -q
mkdir "$repo/PokerStats"
echo x > "$repo/PokerStats/Moved.swift"
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm base
mkdir "$repo/docs"
git -C "$repo" mv PokerStats/Moved.swift docs/Moved.swift
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm move
expect "rename out of app"   "ios=true deno=false"  "$(git -C "$repo" diff --name-only --no-renames HEAD^1 HEAD)"

# git diff prints paths with spaces unquoted, one per line.
mkdir -p "$repo/supabase/my fn"
echo x > "$repo/supabase/my fn/index.ts"
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@t commit -qm space
expect "path with spaces"    "ios=false deno=true"  "$(git -C "$repo" diff --name-only --no-renames HEAD^1 HEAD)"
expect "spaces, two areas"   "ios=true deno=true"   $'PokerStats/My View.swift\nsupabase/my fn/index.ts'

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
