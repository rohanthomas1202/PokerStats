#!/usr/bin/env bash
# Prints TestFlight "What to Test" notes for a release tag: the subject of
# every commit since the previous valid release tag (one ios-release-kind.sh
# accepts), newest first. Squash merges put the PR number in the subject,
# e.g. "Fix restore race (#34)".
# The first release lists the last 30 commits. TestFlight allows 4000
# characters, so longer notes are cut at a line break.
set -euo pipefail

tag=${1:?usage: release-notes.sh <tag>}
limit=4000

dir=$(cd "$(dirname "$0")" && pwd)

# Nearest ios-* tag before $tag, skipping names the workflow would reject.
# The empty-array expansion form keeps macOS bash 3.2 happy under set -u.
previous_release() {
  local exclude=() candidate
  while candidate=$(git describe --tags --abbrev=0 --match 'ios-*' ${exclude[@]+"${exclude[@]}"} "$tag^" 2>/dev/null); do
    if "$dir/ios-release-kind.sh" "$candidate" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
    exclude+=(--exclude "$candidate")
  done
  return 1
}

if previous=$(previous_release); then
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
