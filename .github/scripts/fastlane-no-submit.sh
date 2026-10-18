#!/usr/bin/env bash
# Fails if any file under the given paths (default: fastlane) turns on App
# Store review submission or automatic release. The owner submits by hand.
#
# Catches literal settings only, with a true value (true, yes, on or 1, any
# case), on the same line or the next one:
#   Ruby       key: true, :key => true, key(true), key true, key = true
#   env/YAML   DELIVER_SUBMIT_FOR_REVIEW=yes, ENV["..."] = "on", KEY: "true"
#   CLI flag   --submit_for_review or --automatic_release with no value
# Not detected: variables, options hashes, expressions such as
# `false || true`, and env vars set in the Xcode Cloud UI, which stay a
# manual check.
set -euo pipefail

key='(submit_for_review|automatic_release)'
# A separator may be followed by a newline; a bare space may not.
setting="${key}[]\"'[:blank:]]*((:|=>|=|\\()[[:space:]]*)?[\"']?(true|yes|on|1)([^[:alnum:]_]|\$)"
# [^[:blank:][:print:]] is a line break: grep can't take \n in a pattern.
flag="--${key}[[:blank:]]*([^[:blank:][:print:]]|[;&|)\"'\\]|[[:blank:]]-|\$)"

# -z reads each file as one record so a pattern can span lines.
status=0
files=$(grep -RIilzE -e "$setting" -e "$flag" "${@:-fastlane}") || status=$?
if (( status == 1 )); then
  echo "fastlane does not submit for review or auto-release."
  exit 0
fi
if (( status > 1 )); then
  echo "fastlane-no-submit: grep failed (missing path?)" >&2
  exit 2
fi
while IFS= read -r file; do
  grep -inE "$key" "$file" | sed "s|^|$file:|"
done <<< "$files"
echo "fastlane must never submit for review or auto-release; the owner submits manually." >&2
exit 1
