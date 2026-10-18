#!/bin/sh
# Usage: check_build_numbers.sh <path to PokerStats.app> <expected build number>
#
# Fails unless the app and its embedded widget extension both have
# CFBundleVersion equal to the expected build number, and the same
# CFBundleShortVersionString. App Store Connect rejects an extension whose
# versions differ from the app's.
set -eu

app="$1"
expected="$2"
appex="$app/PlugIns/PokerStatsWidgets.appex"

read_key() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$2/Info.plist"
}

app_build=$(read_key CFBundleVersion "$app")
appex_build=$(read_key CFBundleVersion "$appex")
app_version=$(read_key CFBundleShortVersionString "$app")
appex_version=$(read_key CFBundleShortVersionString "$appex")

echo "PokerStats.app:          CFBundleVersion $app_build, CFBundleShortVersionString $app_version"
echo "PokerStatsWidgets.appex: CFBundleVersion $appex_build, CFBundleShortVersionString $appex_version"

status=0
if [ "$app_build" != "$expected" ]; then
    echo "error: app CFBundleVersion is $app_build, expected $expected"
    status=1
fi
if [ "$appex_build" != "$expected" ]; then
    echo "error: widget extension CFBundleVersion is $appex_build, expected $expected"
    status=1
fi
if [ "$app_version" != "$appex_version" ]; then
    echo "error: widget extension CFBundleShortVersionString $appex_version does not match the app's $app_version"
    status=1
fi
exit $status
