#!/usr/bin/env bash
# Prints TestFlight "What to Test" notes for a release tag: the subject of
# every commit since the previous ios-* tag, newest first. Squash merges put
# the PR number in the subject, e.g. "Fix restore race (#34)".
# The first release lists the last 30 commits. TestFlight allows 4000
# characters, so longer notes are cut at a line break.
set -euo pipefail

tag=${1:?usage: release-notes.sh <tag>}
limit=4000

if previous=$(git describe --tags --abbrev=0 --match 'ios-*' "$tag^" 2>/dev/null); then
  range=("$previous..$tag")
  header="Changes since $previous:"
else
  range=(-30 "$tag")
  header="Recent changes:"
fi

notes="$header"$'\n'"$(git log --no-merges --format='- %s' "${range[@]}")"
if (( ${#notes} > limit )); then
  notes=${notes:0:limit}
  notes=${notes%$'\n'*}
fi
printf '%s\n' "$notes"
