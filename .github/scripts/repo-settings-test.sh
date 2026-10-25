#!/usr/bin/env bash
# Tests for .github/rulesets/*.json and repo-settings-check.sh.
# Run: .github/scripts/repo-settings-test.sh
set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$dir/../.." && pwd)"
main="$root/.github/rulesets/main.json"
tags="$root/.github/rulesets/ios-tags.json"
ci="$root/.github/workflows/ci.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0
ok() { echo "ok   $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
expect() { # name jq-filter file
  if jq -e "$2" "$3" >/dev/null; then ok "$1"; else fail "$1"; fi
}

# The gate job's name: in ci.yml, unquoted.
gate_name() {
  awk '/^  gate:/ { g = 1; next }
       g && /^  [^ #]/ { exit }
       g && /^    name:/ { sub(/^    name: */, ""); gsub(/^["'\'']|["'\'']$/, ""); print; exit }' "$1"
}
# The ruleset must require exactly one check, named like the gate job.
same_check() { # ci.yml main.json
  local name
  name=$(gate_name "$1")
  [[ -n "$name" ]] && jq -e --arg n "$name" \
    '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context] == [$n]' "$2" >/dev/null
}

for f in "$main" "$tags"; do
  if jq empty "$f" 2>/dev/null; then ok "parses: ${f#"$root"/}"; else fail "parses: ${f#"$root"/}"; fi
done

if same_check "$ci" "$main"; then ok "main.json requires the gate job's name ($(gate_name "$ci"))"; else fail "main.json requires the gate job's name"; fi
sed 's/^    name: CI passed$/    name: CI green/' "$ci" > "$tmp/ci.yml"
if [[ "$(gate_name "$tmp/ci.yml")" == "CI green" ]] && ! same_check "$tmp/ci.yml" "$main"; then
  ok "renamed gate job fails the check"
else
  fail "renamed gate job fails the check"
fi

admin='.bypass_actors == [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]'
expect "main: targets the default branch" '.target == "branch" and .conditions.ref_name.include == ["~DEFAULT_BRANCH"]' "$main"
expect "main: active" '.enforcement == "active"' "$main"
expect "main: rules" '[.rules[].type] | sort == ["deletion", "non_fast_forward", "pull_request", "required_status_checks"]' "$main"
expect "main: 0 approvals, no code owner review" \
  '.rules[] | select(.type == "pull_request") | .parameters | .required_approving_review_count == 0 and .require_code_owner_review == false' "$main"
expect "main: check comes from GitHub Actions" \
  '[.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].integration_id] == [15368]' "$main"
expect "main: admin role bypass, Always" "$admin" "$main"
expect "ios-tags: targets ios-* tags" '.target == "tag" and .conditions.ref_name.include == ["refs/tags/ios-*"]' "$tags"
expect "ios-tags: active" '.enforcement == "active"' "$tags"
expect "ios-tags: restricts creations, updates and deletions" '[.rules[].type] | sort == ["creation", "deletion", "update"]' "$tags"
expect "ios-tags: admin role bypass, Always" "$admin" "$tags"

# repo-settings-check.sh against a stand-in gh that serves the two files as
# the repo's rulesets. It only answers "gh api PATH [--jq EXPR]" and logs any
# other call, so a write call (-X, -f, --input, ...) fails the test.
mkdir "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$STUB_LOG"
[[ "$1" == api && ( $# -eq 2 || ( $# -eq 4 && "$3" == --jq ) ) ]] || { echo "REJECTED $*" >> "$STUB_LOG"; exit 99; }
r=repos/o/r
on() { [[ "$STUB_SET" == 1 ]]; }
case "$2" in
  "$r/rules/branches/main") if on; then jq '.rules' "$STUB_MAIN"; else echo '[]'; fi ;;
  "$r/rulesets?per_page=100") if on; then echo '[{"id":1},{"id":2}]'; else echo '[]'; fi ;;
  "$r/rulesets/1") jq "$STUB_FILTER" "$STUB_MAIN" ;;
  "$r/rulesets/2") jq "$STUB_FILTER" "$STUB_TAGS" ;;
  "$r") echo "{\"permissions\":{\"admin\":$STUB_ADMIN}}" ;;
  "$r/vulnerability-alerts") on || { echo "gh: Vulnerability alerts are disabled. (HTTP 404)" >&2; exit 1; } ;;
  "$r/automated-security-fixes") if on; then echo '{"enabled":true}'; else echo '{"enabled":false}'; fi ;;
  *) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
esac | if [[ $# -eq 4 ]]; then jq -r "$4"; else cat; fi
STUB
chmod +x "$tmp/bin/gh"

run_check() { # name set admin filter want-exit want-pass want-fail want-cant-read
  local out code=0
  out=$(PATH="$tmp/bin:$PATH" STUB_LOG="$tmp/log" STUB_MAIN="$main" STUB_TAGS="$tags" \
    STUB_SET="$2" STUB_ADMIN="$3" STUB_FILTER="$4" "$dir/repo-settings-check.sh" o/r) || code=$?
  local got
  got="$code $(grep -c '^pass ' <<<"$out" || true) $(grep -c '^FAIL ' <<<"$out" || true) $(grep -c "^can't read" <<<"$out" || true)"
  if [[ "$got" == "$5 $6 $7 $8" ]]; then ok "check: $1"; else fail "check: $1: want '$5 $6 $7 $8' (exit pass fail can't-read), got '$got'"; echo "$out"; fi
}
run_check "both rulesets and Dependabot on" 1 true  '.'                   0 11 0 0
run_check "nothing set (today)"             0 true  '.'                   1 0 11 0
run_check "no admin, no bypass_actors"      1 false 'del(.bypass_actors)' 1 7 0 4
if grep -q REJECTED "$tmp/log"; then fail "check makes only GET calls: $(grep REJECTED "$tmp/log")"; else ok "check makes only GET calls"; fi

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
