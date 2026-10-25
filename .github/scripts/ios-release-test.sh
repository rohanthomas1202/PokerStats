#!/usr/bin/env bash
# Tests for ios-release-kind.sh, release-notes.sh, fastlane/asc_key.rb,
# ci_scripts/generate_project.sh, and the upload gates and package lock in
# ios-release.yml and the Fastfile.
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

commit "Sixth (#6)"
git tag ios-sprint-3-rc
commit "Seventh (#7)"
git tag ios-v1.1
check "skips invalid ios-* tag" $'Changes since ios-v1.0:\n- Seventh (#7)\n- Sixth (#6)' "$("$dir/release-notes.sh" ios-v1.1)"

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

# Upload gates. Job blocks run from "  <name>:" to the next job key.
job() { awk -v j="  $1:" '$0 == j {grab=1; print; next} grab && /^  [a-z]/ {exit} grab {print}' "$wf"; }
first_step() { awk '/^    steps:/ {grab=1; next} grab && /^      - / {n++} n == 1 {print} n == 2 {exit}' <<<"$1"; }
has() { grep -Eq -- "$1" <<<"$2" && echo yes || echo no; }

check_job=$(job check)
testflight=$(job testflight)
appstore=$(job appstore)
appstore_if=$(grep -E '^    if:' <<<"$appstore" || true)
gate=$(first_step "$appstore")

check "appstore job exists" yes "$( [[ -n "$appstore" ]] && echo yes || echo no)"
check "appstore uses app-store environment" yes "$(has '^    environment: app-store$' "$appstore")"
check "appstore if needs appstore kind" yes "$(has "needs.check.outputs.kind == 'appstore'" "$appstore_if")"
check "appstore if needs a tag ref" yes "$(has "github.ref_type == 'tag'" "$appstore_if")"
check "appstore if needs ios-v ref" yes "$(has "startsWith\(github.ref, 'refs/tags/ios-v'\)" "$appstore_if")"
check "appstore first step reads the enable var" yes "$(has 'vars\.APP_STORE_UPLOAD_ENABLED' "$gate")"
# shellcheck disable=SC2016 # literal $VAR text in the workflow
check "appstore first step fails unless true" yes "$(has '"\$APP_STORE_UPLOAD_ENABLED" != "true"' "$gate")"
check "appstore first step checks tag ref" yes "$(has 'GITHUB_REF_TYPE" != "tag"' "$gate")"
check "appstore first step uses no secrets" no "$(has 'secrets\.' "$gate")"
check "appstore runs fastlane release" yes "$(has 'fastlane ios release' "$appstore")"
check "appstore never runs fastlane beta" no "$(has 'fastlane[[:space:]]+ios[[:space:]]+beta' "$appstore")"

check "testflight job exists" yes "$( [[ -n "$testflight" ]] && echo yes || echo no)"
check "testflight uses testflight environment" yes "$(has '^    environment: testflight$' "$testflight")"
check "testflight never runs fastlane release" no "$(has 'fastlane[[:space:]]+ios[[:space:]]+release' "$testflight")"
check "testflight never mentions appstore kind" no "$(has 'appstore' "$testflight")"
check "testflight needs a sprint tag" yes "$(has "startsWith\(github.ref, 'refs/tags/ios-sprint-'\)" "$testflight")"
check "testflight dispatch is a dry run" yes "$(has 'fastlane ios beta dry_run:true' "$testflight")"

check "no workflow-level env" no "$(has '^env:' "$(cat "$wf")")"
check "check job uses no secrets" no "$(has 'secrets\.' "$check_job")"
check "no .ipa artifact" no "$(has '\.ipa' "$(grep -E '^[[:space:]]+path:' "$wf")")"

# Fastfile: the release lane block runs from "lane :release" to its "  end".
ff="$root/fastlane/Fastfile"
release_lane=$(awk '/^  lane :release/ {grab=1} grab {print} grab && /^  end$/ {exit}' "$ff")
build_app=$(awk '/^  build_app\(/ {grab=1} grab {print} grab && /^  \)$/ {exit}' "$ff")
check "release lane found" yes "$( [[ -n "$release_lane" ]] && echo yes || echo no)"
check "release lane has no force" no "$(has 'force:' "$release_lane")"
check "release lane skips metadata (#53)" yes "$(has 'skip_metadata: true' "$release_lane")"
check "release lane never submits" yes "$(has 'submit_for_review: false' "$release_lane")"
check "build_app export method" yes "$(has 'export_method: "app-store-connect"' "$build_app")"
check "build_app xcargs get signing flags" yes "$(has '^    xcargs: ".*#\{signing\}"' "$build_app")"
check "build_app export_xcargs get signing flags" yes "$(has '^    export_xcargs: signing' "$build_app")"
check "signing flags come from AscKey" yes "$(has 'signing = AscKey.xcodebuild_flags\(key\)' "$(cat "$ff")")"

# Package lock (#218): both upload lanes generate the project through
# generate_project.sh, and build_app resolves only from Package.resolved.
beta_lane=$(awk '/^  lane :beta/ {grab=1} grab {print} grab && /^  end$/ {exit}' "$ff")
check "build_app disables package updates" yes "$(has '^    disable_package_automatic_updates: true$' "$build_app")"
check "build_app does not skip package resolution" no "$(has 'skip_package_dependencies_resolution' "$build_app")"
for lane in beta release; do
  body=$beta_lane; [[ $lane == release ]] && body=$release_lane
  check "$lane lane uses generate_project.sh" yes "$(has 'sh\("cd \.\. && ci_scripts/generate_project\.sh"\)' "$body")"
  check "$lane lane has no bare xcodegen" no "$(has 'xcodegen generate' "$body")"
done
check "ci_post_clone.sh uses generate_project.sh" yes "$(has 'ci_scripts/generate_project\.sh' "$(cat "$root/ci_scripts/ci_post_clone.sh")")"

# generate_project.sh in a throwaway repo, with a stand-in xcodegen that
# deletes Package.resolved the way the real one can.
resolved="PokerStats.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
gen_repo="$tmp/gen"
mkdir -p "$gen_repo/ci_scripts" "$gen_repo/$(dirname "$resolved")"
cp "$root/ci_scripts/generate_project.sh" "$gen_repo/ci_scripts/"
printf '{"pins":["committed"]}\n' > "$gen_repo/$resolved"
cat > "$tmp/xcodegen" <<'SH'
#!/bin/sh
rm -rf PokerStats.xcodeproj/project.xcworkspace
echo generated > generated.txt
SH
chmod +x "$tmp/xcodegen"
git -C "$gen_repo" init -q
git -C "$gen_repo" -c user.name=test -c user.email=test@example.com add -A
git -C "$gen_repo" -c user.name=test -c user.email=test@example.com commit -q -m init
gen() {
  rm -f "$gen_repo/generated.txt"
  XCODEGEN="$tmp/xcodegen" "$gen_repo/ci_scripts/generate_project.sh" 2>&1 && echo "exit 0" || echo "exit $?"
}
out=$(gen)
check "generate: clean tree passes" "exit 0" "$(tail -n1 <<<"$out")"
check "generate: ran xcodegen" yes "$( [[ -f "$gen_repo/generated.txt" ]] && echo yes || echo no)"
check "generate: Package.resolved restored" '{"pins":["committed"]}' "$(cat "$gen_repo/$resolved" 2>/dev/null)"
printf '{"pins":["drifted"]}\n' > "$gen_repo/$resolved"
out=$(gen)
check "generate: drifted file fails" yes "$(grep -q '^exit [1-9]' <<<"$out" && grep -q 'differs from the commit' <<<"$out" && echo yes || echo no)"
check "generate: drift stops before xcodegen" no "$( [[ -f "$gen_repo/generated.txt" ]] && echo yes || echo no)"
rm -f "$gen_repo/$resolved"
out=$(gen)
check "generate: missing file fails" yes "$(grep -q '^exit [1-9]' <<<"$out" && grep -q 'is missing' <<<"$out" && echo yes || echo no)"
git -C "$gen_repo" rm -q --cached "$resolved"
printf '{"pins":["committed"]}\n' > "$gen_repo/$resolved"
out=$(gen)
check "generate: uncommitted file fails" yes "$(grep -q '^exit [1-9]' <<<"$out" && grep -q 'is not committed' <<<"$out" && echo yes || echo no)"

# asc_key.rb, run with plain Ruby.
if ! command -v ruby >/dev/null; then
  echo "FAIL ruby is needed to test fastlane/asc_key.rb"
  failures=$((failures + 1))
else
  rb() { ruby -r"$root/fastlane/asc_key.rb" -e "$1"; }
  check "flags include key path, id, issuer" \
    "-allowProvisioningUpdates -authenticationKeyPath /k/A\\ B.p8 -authenticationKeyID KID -authenticationKeyIssuerID ISS" \
    "$(rb 'puts AscKey.xcodebuild_flags(id: "KID", issuer: "ISS", path: "/k/A B.p8")')"
  mkdir "$tmp/runner"
  out=$(RUNNER_TEMP="$tmp/runner" rb '
    k = AscKey.load("ASC_KEY_ID" => "KID", "ASC_ISSUER_ID" => "ISS", "ASC_PRIVATE_KEY" => "PEM", "RUNNER_TEMP" => ENV["RUNNER_TEMP"])
    puts [File.dirname(k[:path]) == ENV["RUNNER_TEMP"], format("%o", File.stat(k[:path]).mode & 0o777), File.read(k[:path])].join(" ")')
  check "key content goes to a 0600 temp .p8" "true 600 PEM" "$out"
  check "temp .p8 removed at exit" "" "$(ls "$tmp/runner")"
  printf 'PEM\n' > "$tmp/given.p8"
  check "ASC_KEY_PATH used as is" "$tmp/given.p8" \
    "$(rb "puts AscKey.load('ASC_KEY_ID' => 'K', 'ASC_ISSUER_ID' => 'I', 'ASC_KEY_PATH' => '$tmp/given.p8')[:path]")"
  check "missing key fails" error \
    "$(rb 'begin; AscKey.load("ASC_KEY_ID" => "K", "ASC_ISSUER_ID" => "I"); puts "ok"; rescue ArgumentError; puts "error"; end')"
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
