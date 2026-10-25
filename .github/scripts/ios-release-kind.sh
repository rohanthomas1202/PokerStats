#!/usr/bin/env bash
# Prints what an iOS release tag does, or fails for any other tag name.
#   ios-sprint-N      testflight  (sprint-close build for testers)
#   ios-vX.Y[.Z]      appstore    (App Store build; the owner submits by hand)
# Tags are the only way an iOS build is uploaded (#100).
set -euo pipefail

tag=${1:?usage: ios-release-kind.sh <tag>}

if [[ $tag =~ ^ios-sprint-[1-9][0-9]*$ ]]; then
  echo testflight
elif [[ $tag =~ ^ios-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(\.(0|[1-9][0-9]*))?$ ]]; then
  echo appstore
else
  echo "Not an iOS release tag: '$tag'. Use ios-sprint-N or ios-vX.Y[.Z]." >&2
  exit 1
fi
