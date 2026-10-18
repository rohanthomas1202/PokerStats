#!/usr/bin/env bash
# Tests for privacy-api-check.sh. Run: .github/scripts/privacy-api-check-test.sh
set -euo pipefail

script="$(cd "$(dirname "$0")" && pwd)/privacy-api-check.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failures=0

# Writes a PrivacyInfo.xcprivacy declaring each category given (e.g.
# UserDefaults), with one reason each.
manifest() {
  local file="$1" category
  shift
  {
    echo '<?xml version="1.0" encoding="UTF-8"?>'
    echo '<plist version="1.0"><dict><key>NSPrivacyAccessedAPITypes</key><array>'
    for category in "$@"; do
      echo "<dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategory$category</string>"
      echo '<key>NSPrivacyAccessedAPITypeReasons</key><array><string>X000.1</string></array></dict>'
    done
    echo '</array></dict></plist>'
  } > "$file"
}

# expect NAME pass|fail DECLARED FILE CONTENT
# DECLARED is a space-separated category list, "none" for an empty manifest,
# or "missing" for no manifest. FILE is relative to the scanned App/ folder.
expect() {
  local name="$1" want="$2" declared="$3" file="$4" content="$5" got
  rm -rf "$tmp/App" "$tmp/PrivacyInfo.xcprivacy"
  mkdir -p "$tmp/App/$(dirname "$file")"
  printf '%s\n' "$content" > "$tmp/App/$file"
  case "$declared" in
    missing) ;;
    none) manifest "$tmp/PrivacyInfo.xcprivacy" ;;
    *) manifest "$tmp/PrivacyInfo.xcprivacy" $declared ;;
  esac
  if "$script" "$tmp/PrivacyInfo.xcprivacy" "$tmp/App" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  fi
}

expect "no API use"                  pass none         A.swift 'let x = 1'
expect "no API use, no manifest"     pass missing      A.swift 'let x = 1'
expect "declared UserDefaults"       pass UserDefaults A.swift 'let d = UserDefaults.standard'
expect "undeclared UserDefaults"     fail none         A.swift 'let d = UserDefaults.standard'
expect "suiteName, no manifest"      fail missing      A.swift 'let d = UserDefaults(suiteName: "group.x")'
expect "AppStorage"                  fail none         A.swift '@AppStorage("k") var k = false'
expect "other category declared"     fail DiskSpace    A.swift 'let d = UserDefaults.standard'
expect "file timestamp"              fail none         A.swift 'let a = try FileManager.default.attributesOfItem(atPath: p)'
expect "modificationDate key"        fail none         A.swift 'let d = attrs[.modificationDate]'
expect "resource key"                fail none         A.swift 'let v = try url.resourceValues(forKeys: [.contentModificationDateKey])'
expect "stat call"                   fail none         A.swift 'var s = stat(); _ = stat(path, &s)'
expect "declared file timestamp"     pass FileTimestamp A.swift 'let d = attrs[.creationDate]'
expect "getattrlistat"               fail none         A.swift 'let r = getattrlistat(fd, path, &list, &buf, size, 0)'
expect "NSFileModificationDate"      fail none         A.swift 'let d = attrs[NSFileModificationDate]'
expect "NSFileCreationDate"          fail none         A.swift 'let d = attrs[NSFileCreationDate]'
expect "NSURLCreationDateKey"        fail none         A.swift 'let k = NSURLCreationDateKey'
expect "NSURLContentModificationDateKey" fail none     A.swift 'let k = NSURLContentModificationDateKey'
expect "boot time"                   fail none         A.swift 'let t = ProcessInfo.processInfo.systemUptime'
expect "mach_absolute_time"          fail none         A.swift 'let t = mach_absolute_time()'
expect "disk space"                  fail none         A.swift 'let k: URLResourceKey = .volumeAvailableCapacityForImportantUsageKey'
expect "statfs"                      fail none         A.swift 'var s = statfs(); _ = statfs(path, &s)'
expect "keyboards"                   fail none         A.swift 'let m = UITextInputMode.activeInputModes'
expect "declared keyboards"          pass ActiveKeyboards A.swift 'let m = UITextInputMode.activeInputModes'
expect "all declared"                pass "UserDefaults FileTimestamp SystemBootTime DiskSpace ActiveKeyboards" A.swift \
  $'let d = UserDefaults.standard\nlet a = attrs[.creationDate]\nlet t = mach_absolute_time()\nlet s = systemFreeSize\nlet m = UITextInputMode.activeInputModes'

expect "unit test folder ignored"    pass none         PokerStatsTests/A.swift 'let d = UserDefaults.standard'
expect "UI test folder ignored"      pass none         PokerStatsUITests/A.swift 'let d = UserDefaults.standard'
expect "other *Tests folder scanned" fail none         FooTests/A.swift 'let d = UserDefaults.standard'
expect "*Tests.swift file scanned"   fail none         FooTests.swift   'let d = UserDefaults.standard'
expect "non-Swift file ignored"      pass none         notes.md         'UserDefaults.standard'
expect "nested folder scanned"       fail none         Services/Cloud/A.swift 'let d = UserDefaults.standard'

expect "line comment"                pass none         A.swift 'let x = 1 // not UserDefaults'
expect "doc comment"                 pass none         A.swift '/// Wraps stat(path) and UserDefaults.'
expect "block comment"               pass none         A.swift $'/* UserDefaults\n   mach_absolute_time() */\nlet x = 1'
expect "code after block comment"    fail none         A.swift '/* note */ let d = UserDefaults.standard'
expect "URL is not a comment"        fail none         A.swift 'let u = "https://x"; let d = UserDefaults.standard'
expect "nested block comment"        pass none         A.swift $'/* outer /* inner */ UserDefaults */\nlet x = 1'
expect "code after nested comment"   fail none         A.swift '/* a /* b */ c */ let d = UserDefaults.standard'
expect "/* in multi-line string"     fail none         A.swift $'let s = """\n  /* not a comment\n  """\nlet d = UserDefaults.standard\n// */'
expect "multi-line string kept"      fail none         A.swift $'let s = """\n  UserDefaults\n  """'
expect "quote in multi-line string"  fail none         A.swift $'let s = """\n  say "hi" /* \\""" \n  """\nlet d = UserDefaults.standard // */'
expect "lookalike names"             pass none         A.swift $'let statKey = 1\nlet status = state.stats\nfoo.stat(1)\nlet userDefaultsKey = 2'

# A manifest that lists a category without a reason does not declare it.
rm -rf "$tmp/App" && mkdir -p "$tmp/App"
echo 'let d = UserDefaults.standard' > "$tmp/App/A.swift"
cat > "$tmp/PrivacyInfo.xcprivacy" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>NSPrivacyAccessedAPITypes</key><array>
<dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string>
<key>NSPrivacyAccessedAPITypeReasons</key><array/></dict>
</array></dict></plist>
PLIST
if "$script" "$tmp/PrivacyInfo.xcprivacy" "$tmp/App" >/dev/null 2>&1; then
  echo "FAIL no reason: want fail, got pass"; failures=$((failures + 1))
else
  echo "ok   no reason"
fi

# Several paths, as CI passes for the widget target: a file outside the
# widget folder is scanned too.
rm -rf "$tmp/App" "$tmp/Shared" && mkdir -p "$tmp/App" "$tmp/Shared"
echo 'let x = 1' > "$tmp/App/A.swift"
echo 'let d = UserDefaults(suiteName: "group.x")' > "$tmp/Shared/B.swift"
manifest "$tmp/PrivacyInfo.xcprivacy"
if "$script" "$tmp/PrivacyInfo.xcprivacy" "$tmp/App" "$tmp/Shared/B.swift" >/dev/null 2>&1; then
  echo "FAIL shared file: want fail, got pass"; failures=$((failures + 1))
else
  echo "ok   shared file"
fi

# A missing path, or no path at all, must fail, not pass silently.
for args in "$tmp/does-not-exist" ""; do
  if "$script" "$tmp/PrivacyInfo.xcprivacy" $args >/dev/null 2>&1; then
    echo "FAIL missing path '$args': want fail, got pass"; failures=$((failures + 1))
  else
    echo "ok   missing path '${args:+$(basename "$args")}'"
  fi
done

if (( failures > 0 )); then
  echo "$failures test(s) failed"
  exit 1
fi
