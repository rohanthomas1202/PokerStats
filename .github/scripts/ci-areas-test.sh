#!/usr/bin/env bash
# Tests for ci-areas.sh. Run: .github/scripts/ci-areas-test.sh
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
script="$dir/ci-areas.sh"
failures=0
repo=$(mktemp -d)
trap 'rm -rf "$repo"' EXIT

expect() {
  local name="$1" want="$2" input="$3" got
  got=$(printf '%s' "$input" | tr '\n' '\0' | "$script" | paste -sd' ' -)
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

expect "spaces, two areas"   "ios=true deno=true"   $'PokerStats/My View.swift\nsupabase/my fn/index.ts'

# The cases below commit a change to a scratch repo and run the workflow's own
# ci-changed-files.sh on it, so they cover the real git diff flags.
git -C "$repo" init -q
commit() { git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm "$1"; }
expect_commit() {
  local name="$1" want="$2" got
  commit "$name"
  got=$(cd "$repo" && "$dir/ci-changed-files.sh" | "$script" | paste -sd' ' -)
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want '$want', got '$got'"
    failures=$((failures + 1))
  fi
}

mkdir "$repo/PokerStats" "$repo/docs"
echo x > "$repo/PokerStats/Moved.swift"
commit base

git -C "$repo" mv PokerStats/Moved.swift docs/Moved.swift
expect_commit "rename out of app"  "ios=true deno=false"

mkdir -p "$repo/supabase/my fn"
echo x > "$repo/supabase/my fn/index.ts"
expect_commit "path with spaces"   "ios=false deno=true"

echo x > "$repo/PokerStats/Café.swift"
expect_commit "non-ASCII path"     "ios=true deno=false"

echo x > "$repo/PokerStats/Say \"hi\".swift"
expect_commit "path with a quote"  "ios=true deno=false"

echo x > "$repo/PokerStats/a"$'\t'"b.swift"
expect_commit "path with a tab"    "ios=true deno=false"

echo x > "$repo/PokerStats/a\\b.swift"
expect_commit "path with a backslash" "ios=true deno=false"

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
