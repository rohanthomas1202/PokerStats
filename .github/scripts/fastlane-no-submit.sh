#!/usr/bin/env bash
# Fails if any file under the given paths (default: fastlane) turns on App
# Store review submission or automatic release. The owner submits by hand.
#
# Catches literal settings only, with a true value (true, yes, on or 1, any
# case), on the same line or the next one:
#   Ruby       key: true, :key => true, key(true), key true, key = true,
#              store(:key, true) (a positional symbol key),
#              send(:key=, true) (a setter symbol),
#              ENV.fetch("DELIVER_AUTOMATIC_RELEASE", "true") (the env var
#              name contains the key), key: ENV.fetch("ANY_NAME", "true"),
#              each also without parentheses (ENV.fetch "X", "true") and with
#              nested defaults (ENV.fetch("A", ENV.fetch("B", "true")))
#   env/YAML   DELIVER_SUBMIT_FOR_REVIEW=yes, ENV["..."] = "on", KEY: "true",
#              KEY: !!bool true, KEY: !!int 1, KEY: &anchor true
#   CLI flag   --submit_for_review or --automatic_release with no value
# Not detected: variables, options hashes, expressions such as
# `false || true`, an ENV.fetch block default (`ENV.fetch("KEY") { "true" }`),
# a comment line between the key and its value (or between an ENV.fetch
# comma and its default), and env vars set in the Xcode Cloud UI, which stay
# a manual check.
# Known false positives: a quoted key or a symbol key (leading colon)
# followed by a comma and a true word, even in a comment, as in
# `"submit_for_review", on any lane` or `# options like :submit_for_review,
# on demand only`. Unquoted prose without a colon, such as
# `submit_for_review, on any lane`, passes.
set -euo pipefail

key='(submit_for_review|automatic_release)'
# A separator may be followed by a newline; a bare space may not. A comma
# counts only right after a closing quote, as in ENV.fetch("KEY", "true"), or
# after a symbol key, as in store(:submit_for_review, true) or the setter
# send(:submit_for_review=, true), so prose like "submit_for_review, on any
# lane" passes. The value may sit inside ENV.fetch's default (with or without
# parentheses, nested too), behind YAML tags (!!bool, !!int) or an anchor
# (&name; a shell && is not an anchor).
fetch="(ENV\\.fetch(\\(|[[:blank:]]+)[^,)]*,[[:space:]]*)*"
sep="([]\"'[:blank:]]*((:|=>|=|\\()[[:space:]]*)?|[\"'][[:blank:]]*,[[:space:]]*)"
yaml="((!![[:alnum:]]+|&[[:alnum:]_-]+)[[:blank:]]+){0,2}"
setting="(${key}${sep}|:${key}=?[[:blank:]]*,[[:space:]]*)${fetch}${yaml}[\"']?(true|yes|on|1)([^[:alnum:]_]|\$)"
# [^[:blank:][:print:]] is a line break: grep can't take \n in a pattern.
flag="--${key}[[:blank:]]*([^[:blank:][:print:]]|[;&|)\"'\\]|[[:blank:]]-|\$)"

# -z reads each file as one record so a pattern can span lines.
status=0
files=$(grep -RIilzE -e "$setting" -e "$flag" "${@:-fastlane}") || status=$?
if (( status == 1 )); then
  echo "fastlane does not submit for review or auto-release."
  exit 0
fi
# grep exits 2 on a missing path even when other paths matched; name the
# matches first so a real setting isn't hidden behind the path error.
if [[ -n "$files" ]]; then
  while IFS= read -r file; do
    grep -inE "$key" "$file" | sed "s|^|$file:|"
  done <<< "$files"
  echo "fastlane must never submit for review or auto-release; the owner submits manually." >&2
fi
if (( status > 1 )); then
  echo "fastlane-no-submit: grep failed (missing path?)" >&2
  exit 2
fi
exit 1
