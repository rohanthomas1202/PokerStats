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

# A missing path must fail, not pass silently.
if "$script" "$tmp/does-not-exist" >/dev/null 2>&1; then
  echo "FAIL missing path: want fail, got pass"
  failures=$((failures + 1))
else
  echo "ok   missing path"
fi

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
