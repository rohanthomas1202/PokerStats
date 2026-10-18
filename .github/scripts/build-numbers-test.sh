#!/usr/bin/env bash
# Tests for ci_scripts/build_number.sh, ci_scripts/check_build_numbers.sh and
# the Fastfile lines that call them. check_build_numbers.sh runs on fake app
# bundles with a Python stand-in for PlistBuddy, so this runs on Linux.
# Run: .github/scripts/build-numbers-test.sh
set -euo pipefail

dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$dir/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

check() {
  local name="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want '$want', got '$got'"
    failures=$((failures + 1))
  fi
}

# build_number.sh
first=$("$root/ci_scripts/build_number.sh")
sleep 1
second=$("$root/ci_scripts/build_number.sh")
check "build number is 14 digits" yes "$([[ "$first" =~ ^[0-9]{14}$ ]] && echo yes || echo no)"
check "runs a second apart differ" yes "$([[ "$first" != "$second" ]] && echo yes || echo no)"
check "later run is higher" yes "$([[ "$second" > "$first" ]] && echo yes || echo no)"

# Stand-in for /usr/libexec/PlistBuddy. Supports only: -c "Print :Key" <plist>.
export PLISTBUDDY="$tmp/PlistBuddy"
cat > "$PLISTBUDDY" <<'PY'
#!/usr/bin/env python3
import plistlib, sys
key = sys.argv[2].removeprefix("Print :")
with open(sys.argv[3], "rb") as f:
    print(plistlib.load(f)[key])
PY
chmod +x "$PLISTBUDDY"

# bundle <dir> <CFBundleVersion> <CFBundleShortVersionString>
bundle() {
  mkdir -p "$1"
  python3 -c 'import plistlib, sys
with open(sys.argv[1] + "/Info.plist", "wb") as f:
    plistlib.dump({"CFBundleVersion": sys.argv[2], "CFBundleShortVersionString": sys.argv[3]}, f)' "$1" "$2" "$3"
}

# Prints the script's output, then "exit <status>".
run_check() {
  "$root/ci_scripts/check_build_numbers.sh" "$@" 2>&1 && echo "exit 0" || echo "exit $?"
}
has() { grep -Fq -- "$1" <<<"$2" && echo yes || echo no; }

n=20261018143005
app="$tmp/ok/PokerStats.app"
bundle "$app" "$n" 1.0
bundle "$app/PlugIns/PokerStatsWidgets.appex" "$n" 1.0
bundle "$app/PlugIns/Another.appex" "$n" 1.0
out=$(run_check "$app" "$n")
check "all match passes" yes "$(has "exit 0" "$out")"
check "checks the widget extension" yes "$(has "PokerStatsWidgets.appex: CFBundleVersion $n" "$out")"
check "checks every .appex" yes "$(has "Another.appex: CFBundleVersion $n" "$out")"

out=$(run_check "$app" 20261018143006)
check "app build mismatch fails" yes "$(has "exit 1" "$out")"
check "app build mismatch names the app" yes "$(has "error: PokerStats.app CFBundleVersion is $n, expected 20261018143006" "$out")"

app="$tmp/bad-build/PokerStats.app"
bundle "$app" "$n" 1.0
bundle "$app/PlugIns/PokerStatsWidgets.appex" "$n" 1.0
bundle "$app/PlugIns/Another.appex" 202610181430 1.0
out=$(run_check "$app" "$n")
check "mismatched .appex build fails" yes "$(has "exit 1" "$out")"
check "mismatched .appex is named" yes "$(has "error: Another.appex CFBundleVersion is 202610181430, expected $n" "$out")"

app="$tmp/bad-version/PokerStats.app"
bundle "$app" "$n" 1.1
bundle "$app/PlugIns/PokerStatsWidgets.appex" "$n" 1.0
out=$(run_check "$app" "$n")
check "mismatched .appex version fails" yes "$(has "exit 1" "$out")"
check "mismatched .appex version is named" yes "$(has "error: PokerStatsWidgets.appex CFBundleShortVersionString 1.0 does not match the app's 1.1" "$out")"

app="$tmp/no-plugins/PokerStats.app"
bundle "$app" "$n" 1.0
out=$(run_check "$app" "$n")
check "no PlugIns folder fails" yes "$(has "exit 1" "$out")"
check "no PlugIns folder says why" yes "$(has "error: no .appex in $app/PlugIns" "$out")"

mkdir "$app/PlugIns"
bundle "$app/PlugIns/NotAnExtension.bundle" "$n" 1.0
out=$(run_check "$app" "$n")
check "PlugIns with no .appex fails" yes "$(has "error: no .appex in $app/PlugIns" "$out")"

app="$tmp/no-plist/PokerStats.app"
bundle "$app" "$n" 1.0
mkdir -p "$app/PlugIns/Empty.appex"
out=$(run_check "$app" "$n")
check ".appex without Info.plist fails" no "$(has "exit 0" "$out")"

# The Fastfile's check line, run as written with a stubbed sh, on an archive
# path with a space and a single quote.
ff="$root/fastlane/Fastfile"
line=$(grep -E '^  sh\(.*ci_scripts/check_build_numbers\.sh' "$ff" || true)
check "Fastfile calls check_build_numbers.sh once" 1 "$(grep -c 'ci_scripts/check_build_numbers\.sh' "$ff")"
app="$tmp/Rohan's Archive 1/PokerStats.app"
bundle "$app" "$n" 1.0
bundle "$app/PlugIns/PokerStatsWidgets.appex" "$n" 1.0
out=$(cd "$root/fastlane" && ruby -rshellwords -e '
  def sh(cmd); system(cmd) || abort("sh failed: #{cmd}"); end
  app, build_number = ARGV[0], ARGV[1]
  eval(ARGV[2])
  puts "exit 0"' "$app" "$n" "$line" 2>&1) || true
check "Fastfile line escapes a quoted path" yes "$(has "exit 0" "$out")"
check "Fastfile line passes the path through" yes "$(has "PokerStatsWidgets.appex: CFBundleVersion $n" "$out")"

build_app=$(awk '/^  build_app\(/ {grab=1} grab {print} grab && /^  \)$/ {exit}' "$ff")
check "export keeps the archived build number" yes "$(has 'export_options: { manageAppVersionAndBuildNumber: false },' "$build_app")"

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
echo "all build number tests passed"
