#!/usr/bin/env bash
# Read-only check of the repo settings from #25 and README Owner setup step 4:
# the main and ios-* tag rulesets (.github/rulesets/) and the Dependabot
# toggles. Only GET requests through gh api; it changes nothing.
# Prints "pass", "FAIL" or "can't read" per setting and exits 1 if any item
# is not "pass". Run: .github/scripts/repo-settings-check.sh [owner/repo]
set -euo pipefail

repo="${1:-rohanthomas1202/PokerStats}"
bad=0
err=$(mktemp)
trap 'rm -f "$err"' EXIT

report() { # status name [detail]
  printf '%-10s %s%s\n' "$1" "$2" "${3:+ ($3)}"
  [[ "$1" == pass ]] || bad=1
}
check() { # name jq-filter-on-$json
  if jq -e "$2" >/dev/null <<<"$json"; then report pass "$1"; else report FAIL "$1"; fi
}

# Active rules on main, from any ruleset. Readable with read access.
if json=$(gh api "repos/$repo/rules/branches/main" 2>"$err"); then
  check "main: pull request required" 'any(.[]; .type == "pull_request")'
  check "main: required status checks are exactly \"CI passed\"" \
    '[.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] | unique == ["CI passed"]'
  check "main: force pushes blocked" 'any(.[]; .type == "non_fast_forward")'
  check "main: deletion blocked" 'any(.[]; .type == "deletion")'
else
  report "can't read" "main: active rules" "$(tr -d '\n' <"$err")"
fi

# Each ruleset in full. bypass_actors is only returned to logins with write
# access to the ruleset.
rulesets='[]'
if ids=$(gh api "repos/$repo/rulesets?per_page=100" --jq '.[].id' 2>"$err"); then
  for id in $ids; do
    if r=$(gh api "repos/$repo/rulesets/$id" 2>"$err"); then
      rulesets=$(jq -c --argjson r "$r" '. + [$r]' <<<"$rulesets")
    else
      report "can't read" "ruleset $id" "$(tr -d '\n' <"$err")"
    fi
  done
else
  report "can't read" "rulesets" "$(tr -d '\n' <"$err")"
fi

admin_bypass='any(.bypass_actors[]?; .actor_type == "RepositoryRole" and .actor_id == 5 and .bypass_mode == "always")'
bypass() { # name ruleset-selector
  json=$(jq -c "[.[] | select(.enforcement == \"active\") | $2]" <<<"$rulesets")
  if jq -e 'length > 0 and all(.[]; has("bypass_actors") | not)' >/dev/null <<<"$json"; then
    report "can't read" "$1" "bypass_actors not returned to this login"
  else
    check "$1" "any(.[]; $admin_bypass)"
  fi
}
bypass "main: Repository admin role bypasses, mode Always" \
  'select(.target == "branch" and any(.conditions.ref_name.include[]; . == "~DEFAULT_BRANCH" or . == "refs/heads/main" or . == "~ALL"))'

tags='select(.target == "tag" and any(.conditions.ref_name.include[]; . == "refs/tags/ios-*"))'
json=$(jq -c "[.[] | select(.enforcement == \"active\") | $tags | [.rules[].type]]" <<<"$rulesets")
check "ios-* tags: creations restricted" 'any(.[]; index("creation"))'
check "ios-* tags: updates restricted" 'any(.[]; index("update"))'
check "ios-* tags: deletions restricted" 'any(.[]; index("deletion"))'
bypass "ios-* tags: Repository admin role bypasses, mode Always" "$tags"

# Both Dependabot endpoints need admin access to the repo.
if [[ "$(gh api "repos/$repo" --jq '.permissions.admin')" != true ]]; then
  report "can't read" "Dependabot alerts" "needs admin access"
  report "can't read" "Dependabot security updates" "needs admin access"
else
  # 204 when on, 404 "Vulnerability alerts are disabled." when off.
  if gh api "repos/$repo/vulnerability-alerts" >/dev/null 2>"$err"; then
    report pass "Dependabot alerts"
  elif grep -q 'alerts are disabled' "$err"; then
    report FAIL "Dependabot alerts"
  else
    report "can't read" "Dependabot alerts" "$(tr -d '\n' <"$err")"
  fi
  if json=$(gh api "repos/$repo/automated-security-fixes" 2>"$err"); then
    check "Dependabot security updates" '.enabled == true'
  elif grep -q 'HTTP 404' "$err"; then
    report FAIL "Dependabot security updates"
  else
    report "can't read" "Dependabot security updates" "$(tr -d '\n' <"$err")"
  fi
fi

exit "$bad"
