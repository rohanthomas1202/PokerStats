#!/usr/bin/env bash
# Prints the paths a pull request changes, NUL-separated and unquoted, for
# ci-areas.sh. Run from the repo root on the merge commit; HEAD^1 is the base
# branch tip. --no-renames lists a moved file under its old path too.
set -euo pipefail

git -c core.quotePath=false diff --name-only -z --no-renames HEAD^1 HEAD
