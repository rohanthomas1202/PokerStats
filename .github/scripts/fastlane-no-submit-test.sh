#!/usr/bin/env bash
# Tests for fastlane-no-submit.sh. Run: .github/scripts/fastlane-no-submit-test.sh
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/fastlane-no-submit.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
# The paths ci.yml passes to the guard.
dirs=(fastlane .github/workflows ci_scripts)

# expect NAME pass|fail PATH CONTENT  (PATH is relative to the repo root)
expect() {
  local name="$1" want="$2" file="$3" content="$4" got
  rm -rf "$tmp/repo"
  for dir in "${dirs[@]}"; do mkdir -p "$tmp/repo/$dir"; done
  printf '%s\n' "$content" > "$tmp/repo/$file"
  if (cd "$tmp/repo" && "$script" "${dirs[@]}") >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  fi
}

expect "current release lane"   pass fastlane/Fastfile    'upload_to_app_store(submit_for_review: false, automatic_release: false)'
expect "comment mentioning it"  pass fastlane/Fastfile    '# Never set submit_for_review to true.'
expect "comment across lines"   pass fastlane/Fastfile    $'# Never set submit_for_review to\n# true.'
expect "unrelated true"         pass fastlane/Fastfile    'skip_metadata: true'
expect "lookalike value"        pass fastlane/Fastfile    'submit_for_review: true_if_owner'
expect "lookalike on"           pass fastlane/Fastfile    'submit_for_review: only_if_owner'
expect "next line false"        pass fastlane/Fastfile    $'upload_to_app_store(\n  submit_for_review:\n    false)'
expect "flag with false"        pass ci_scripts/release.sh 'fastlane deliver --submit_for_review false'
expect "flag lookalike"         pass ci_scripts/release.sh 'fastlane deliver --submit_for_review_later'
expect "workflow false"         pass .github/workflows/x.yml $'env:\n  DELIVER_SUBMIT_FOR_REVIEW: "false"'
expect "ENV.fetch false"        pass fastlane/Fastfile    'ENV.fetch("DELIVER_AUTOMATIC_RELEASE", "false")'
expect "false, then other true" pass fastlane/Fastfile    'upload_to_app_store(submit_for_review: false, skip_metadata: true)'
expect "comment, comma then on" pass fastlane/Fastfile    '# never set submit_for_review, on any lane'
expect "comment, comma then 1"  pass ci_scripts/release.sh '# automatic_release, 1 of the keys we never set'
expect "fetch other var false"  pass fastlane/Fastfile    'upload_to_app_store(submit_for_review: ENV.fetch("X", "false"))'

expect "submit key: true"       fail fastlane/Fastfile    'upload_to_app_store(submit_for_review: true)'
expect "release key: true"      fail fastlane/Fastfile    'upload_to_app_store(automatic_release: true)'
expect "hash rocket"            fail fastlane/Fastfile    'deliver(:submit_for_review => true)'
expect "no space"               fail fastlane/Fastfile    'deliver(automatic_release:true)'
expect "Deliverfile call"       fail fastlane/Deliverfile 'submit_for_review(true)'
expect "Deliverfile bare"       fail fastlane/Deliverfile 'automatic_release true'
expect "assignment"             fail fastlane/Fastfile    'submit_for_review = true'
expect "dotenv"                 fail fastlane/.env        'DELIVER_SUBMIT_FOR_REVIEW=true'
expect "dotenv quoted"          fail fastlane/.env        'DELIVER_AUTOMATIC_RELEASE="true"'
expect "ENV hash"               fail fastlane/Fastfile    'ENV["DELIVER_SUBMIT_FOR_REVIEW"] = "true"'

expect "dotenv yes"             fail fastlane/.env        'DELIVER_SUBMIT_FOR_REVIEW=yes'
expect "quoted on"              fail fastlane/Fastfile    'upload_to_app_store(submit_for_review: "on")'
expect "upper case YES"         fail fastlane/Fastfile    'upload_to_app_store(automatic_release: YES)'
expect "mixed case True"        fail fastlane/Fastfile    'upload_to_app_store(submit_for_review: True)'
expect "one"                    fail fastlane/.env        'DELIVER_AUTOMATIC_RELEASE=1'
expect "workflow env"           fail .github/workflows/x.yml $'env:\n  DELIVER_SUBMIT_FOR_REVIEW: "true"'
expect "workflow export"        fail .github/workflows/x.yml $'run: |\n  export DELIVER_AUTOMATIC_RELEASE=on'
expect "ci_scripts export"      fail ci_scripts/release.sh 'export DELIVER_SUBMIT_FOR_REVIEW=yes'
expect "value on next line"     fail fastlane/Fastfile    $'upload_to_app_store(\n  submit_for_review:\n    true)'
expect "rocket, next line"      fail fastlane/Fastfile    $'deliver(:automatic_release =>\n  true)'
expect "bare flag"              fail ci_scripts/release.sh 'fastlane deliver --submit_for_review'
expect "bare flag, more flags"  fail ci_scripts/release.sh 'fastlane deliver --automatic_release --force'
expect "bare flag, continued"   fail .github/workflows/x.yml $'run: fastlane deliver --submit_for_review \\\n  --force'
expect "flag with yes"          fail ci_scripts/release.sh 'fastlane deliver --automatic_release yes'
expect "flag equals true"       fail ci_scripts/release.sh 'fastlane deliver --submit_for_review=true'
expect "ENV.fetch default"      fail fastlane/Fastfile    'ENV.fetch("DELIVER_AUTOMATIC_RELEASE", "true")'
expect "ENV.fetch no quotes"    fail fastlane/Fastfile    "ENV.fetch('DELIVER_SUBMIT_FOR_REVIEW', true)"
expect "YAML bool tag"          fail .github/workflows/x.yml $'with:\n  submit_for_review: !!bool true'
expect "YAML int tag"           fail .github/workflows/x.yml $'with:\n  submit_for_review: !!int 1'
expect "YAML anchor"            fail .github/workflows/x.yml $'with:\n  submit_for_review: &a true'
expect "YAML anchor and tag"    fail .github/workflows/x.yml $'with:\n  automatic_release: &a !!bool yes'
expect "fetch other var default" fail fastlane/Fastfile   'upload_to_app_store(submit_for_review: ENV.fetch("X", "true"))'
expect "fetch default next line" fail fastlane/Fastfile   $'upload_to_app_store(automatic_release: ENV.fetch("X",\n  "true"))'

# expect_status NAME WANT_STATUS PATH...  (runs from the scratch repo)
expect_status() {
  local name="$1" want="$2" got=0
  shift 2
  (cd "$tmp/repo" && "$script" "$@") >"$tmp/out" 2>&1 || got=$?
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want exit $want, got $got"
    failures=$((failures + 1))
  fi
}

# A missing path must fail, not pass silently.
rm -rf "$tmp/repo"
mkdir -p "$tmp/repo"
expect_status "missing path" 2 does-not-exist

# A missing path next to a path with a match: grep exits 2 with output, and
# the guard must still fail.
for dir in "${dirs[@]}"; do mkdir -p "$tmp/repo/$dir"; done
printf '%s\n' 'upload_to_app_store(submit_for_review: true)' > "$tmp/repo/fastlane/Fastfile"
expect_status "missing path next to a match" 2 "${dirs[@]}" does-not-exist
if grep -q "^fastlane/Fastfile:" "$tmp/out"; then
  echo "ok   missing path next to a match: names fastlane/Fastfile"
else
  echo "FAIL missing path next to a match: fastlane/Fastfile not in output"
  failures=$((failures + 1))
fi

# Two paths matching at once: fail and name both files.
printf '%s\n' 'export DELIVER_AUTOMATIC_RELEASE=yes' > "$tmp/repo/ci_scripts/release.sh"
expect_status "two paths match" 1 "${dirs[@]}"
for file in fastlane/Fastfile ci_scripts/release.sh; do
  if grep -q "^$file:" "$tmp/out"; then
    echo "ok   two paths match: names $file"
  else
    echo "FAIL two paths match: $file not in output"
    failures=$((failures + 1))
  fi
done

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
