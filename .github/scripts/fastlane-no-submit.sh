#!/usr/bin/env bash
# Fails if any file under the given directories (default: fastlane) turns on
# App Store review submission or automatic release. The owner submits by hand.
# Catches Ruby (key: true, :key => true, key(true), key true), assignment
# (key = true) and env (SUBMIT_FOR_REVIEW=true, ENV["DELIVER_..."] = "true").
set -euo pipefail

pattern='(submit_for_review|automatic_release)[]"'"'"'[:space:]]*(:|=>|=|\()?[[:space:]]*["'"'"']?true([^[:alnum:]_]|$)'

if grep -RIinE "$pattern" "${@:-fastlane}"; then
  echo "fastlane must never submit for review or auto-release; the owner submits manually." >&2
  exit 1
fi
echo "fastlane does not submit for review or auto-release."
