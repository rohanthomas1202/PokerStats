#!/usr/bin/env bash
# Tests for fastlane-no-submit.sh. Run: .github/scripts/fastlane-no-submit-test.sh
set -euo pipefail

script="$(dirname "$0")/fastlane-no-submit.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

# expect NAME pass|fail FILENAME CONTENT
expect() {
  local name="$1" want="$2" file="$3" content="$4" got
  rm -rf "$tmp/fastlane" && mkdir -p "$tmp/fastlane"
  printf '%s\n' "$content" > "$tmp/fastlane/$file"
  if "$script" "$tmp/fastlane" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  fi
}

expect "current release lane"   pass Fastfile    'upload_to_app_store(submit_for_review: false, automatic_release: false)'
expect "comment mentioning it"  pass Fastfile    '# Never set submit_for_review to true.'
expect "unrelated true"         pass Fastfile    'skip_metadata: true'
expect "lookalike value"        pass Fastfile    'submit_for_review: true_if_owner'
expect "submit key: true"       fail Fastfile    'upload_to_app_store(submit_for_review: true)'
expect "release key: true"      fail Fastfile    'upload_to_app_store(automatic_release: true)'
expect "hash rocket"            fail Fastfile    'deliver(:submit_for_review => true)'
expect "no space"               fail Fastfile    'deliver(automatic_release:true)'
expect "Deliverfile call"       fail Deliverfile 'submit_for_review(true)'
expect "Deliverfile bare"       fail Deliverfile 'automatic_release true'
expect "assignment"             fail Fastfile    'submit_for_review = true'
expect "dotenv"                 fail .env        'DELIVER_SUBMIT_FOR_REVIEW=true'
expect "dotenv quoted"          fail .env        'DELIVER_AUTOMATIC_RELEASE="true"'
expect "ENV hash"               fail Fastfile    'ENV["DELIVER_SUBMIT_FOR_REVIEW"] = "true"'

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
