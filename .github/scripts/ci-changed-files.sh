#!/usr/bin/env bash
# Prints the paths a pull request changes, NUL-separated and unquoted, for
# ci-areas.sh. Run from the repo root on the merge commit; HEAD^1 is the base
# branch tip. --no-renames lists a moved file under its old path too. -z
# prints paths verbatim, so core.quotePath does not apply.
set -euo pipefail

git diff --name-only -z --no-renames HEAD^1 HEAD
