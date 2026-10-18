#!/usr/bin/env bash
# Tests for ios-release-kind.sh, release-notes.sh, and ios-release.yml scoping.
# Run: .github/scripts/ios-release-test.sh
set -euo pipefail

dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$dir/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

check() {
  local name="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want '$want', got '$got'"
    failures=$((failures + 1))
  fi
}

kind() { "$dir/ios-release-kind.sh" "$1" 2>/dev/null || echo rejected; }

check "sprint tag"          testflight "$(kind ios-sprint-1)"
check "sprint two digits"   testflight "$(kind ios-sprint-12)"
check "version X.Y"         appstore   "$(kind ios-v1.0)"
check "version X.Y.Z"       appstore   "$(kind ios-v1.0.1)"
check "version ten"         appstore   "$(kind ios-v1.10)"
check "old sprint tag"      rejected   "$(kind sprint-3)"
check "plain version"       rejected   "$(kind v1.0)"
check "sprint zero"         rejected   "$(kind ios-sprint-0)"
check "sprint no number"    rejected   "$(kind ios-sprint-)"
check "sprint suffix"       rejected   "$(kind ios-sprint-3-rc)"
check "version major only"  rejected   "$(kind ios-v1)"
check "version suffix"      rejected   "$(kind ios-v1.0-beta)"
check "version leading 0"   rejected   "$(kind ios-v01.0)"
check "web tag"             rejected   "$(kind web-v1.0)"
check "empty"               rejected   "$(kind '')"

# release-notes.sh against a throwaway repo.
git init -q "$tmp/repo"
cd "$tmp/repo"
git config user.name test && git config user.email test@example.com
commit() { git commit -q --allow-empty -m "$1"; }

commit "First (#1)"
commit "Second (#2)"
git tag ios-sprint-1
check "first release" $'Recent changes:\n- Second (#2)\n- First (#1)' "$("$dir/release-notes.sh" ios-sprint-1)"

commit "Third (#3)"
git tag web-v1.0
commit "Fourth (#4)"
git tag ios-sprint-2
check "since previous ios tag" $'Changes since ios-sprint-1:\n- Fourth (#4)\n- Third (#3)' "$("$dir/release-notes.sh" ios-sprint-2)"

commit "Fifth (#5)"
git tag ios-v1.0
check "version after sprint" $'Changes since ios-sprint-2:\n- Fifth (#5)' "$("$dir/release-notes.sh" ios-v1.0)"

long=$(printf 'x%.0s' {1..300})
for i in $(seq 1 20); do commit "$long $i"; done
git tag ios-sprint-3
notes=$("$dir/release-notes.sh" ios-sprint-3)
check "cut to 4000 chars" yes "$( (( ${#notes} <= 4000 )) && echo yes || echo no)"
check "cut at a line break" "- $long 8" "$(tail -n1 <<<"$notes")"

# Workflow trigger scoping: ios-release.yml must not run on ordinary pushes/PRs.
wf="$root/.github/workflows/ios-release.yml"
ci="$root/.github/workflows/ci.yml"

if [[ ! -f "$wf" ]]; then
  echo "FAIL missing ios-release.yml"
  failures=$((failures + 1))
else
  on_block=$(awk '
    /^on:/ {grab=1; next}
    grab && /^[a-zA-Z]/ {exit}
    grab {print}
  ' "$wf")
  check "workflow has tag trigger" yes "$(grep -q 'tags:' <<<"$on_block" && echo yes || echo no)"
  check "workflow has workflow_dispatch" yes "$(grep -q 'workflow_dispatch' <<<"$on_block" && echo yes || echo no)"
  check "workflow has no pull_request" yes "$(grep -q 'pull_request' <<<"$on_block" && echo no || echo yes)"
  check "workflow has no branches push" yes "$(grep -q 'branches:' <<<"$on_block" && echo no || echo yes)"
  check "workflow concurrency ios-release" yes "$(grep -q 'group: ios-release' "$wf" && echo yes || echo no)"
  check "workflow calls beta for sprint" yes "$(grep -q 'fastlane ios beta' "$wf" && echo yes || echo no)"
  check "workflow calls release for appstore" yes "$(grep -q 'fastlane ios release' "$wf" && echo yes || echo no)"
  check "workflow never submit_for_review true" yes "$(grep -Eiq 'submit_for_review.*true' "$wf" && echo no || echo yes)"
fi

if [[ -f "$ci" ]]; then
  check "ci.yml does not call fastlane beta" yes "$(grep -Eq 'fastlane[[:space:]]+ios[[:space:]]+beta' "$ci" && echo no || echo yes)"
  check "ci.yml does not call fastlane release" yes "$(grep -Eq 'fastlane[[:space:]]+ios[[:space:]]+release' "$ci" && echo no || echo yes)"
fi

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all ios-release tests passed"
