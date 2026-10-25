#!/bin/sh
# Usage: check_build_numbers.sh <path to PokerStats.app> <expected build number>
#
# Fails unless the app and every extension in its PlugIns folder have
# CFBundleVersion equal to the expected build number, and every extension
# has the app's CFBundleShortVersionString. App Store Connect rejects an
# extension whose versions differ from the app's. Also fails if
# PlugIns/PokerStatsWidgets.appex is missing, since the app ships with its
# widget extension; another .appex does not count for it.
#
# Only PlugIns/*.appex is scanned. An ExtensionKit extension under
# Extensions/, an App Clip, or an extension nested inside another bundle is
# not checked: extend this script before adding a target like that.
#
# PLISTBUDDY replaces /usr/libexec/PlistBuddy, so
# .github/scripts/build-numbers-test.sh can run on Linux.
set -eu

app="$1"
expected="$2"
plistbuddy="${PLISTBUDDY:-/usr/libexec/PlistBuddy}"

read_key() {
    "$plistbuddy" -c "Print :$1" "$2/Info.plist"
}

app_version=$(read_key CFBundleShortVersionString "$app")
status=0

check_bundle() {
    name=$(basename "$1")
    build=$(read_key CFBundleVersion "$1")
    version=$(read_key CFBundleShortVersionString "$1")
    echo "$name: CFBundleVersion $build, CFBundleShortVersionString $version"
    if [ "$build" != "$expected" ]; then
        echo "error: $name CFBundleVersion is $build, expected $expected"
        status=1
    fi
    if [ "$version" != "$app_version" ]; then
        echo "error: $name CFBundleShortVersionString $version does not match the app's $app_version"
        status=1
    fi
}

check_bundle "$app"
for appex in "$app"/PlugIns/*.appex; do
    [ -d "$appex" ] || continue
    check_bundle "$appex"
done
if [ ! -d "$app/PlugIns/PokerStatsWidgets.appex" ]; then
    echo "error: no PokerStatsWidgets.appex in $app/PlugIns"
    status=1
fi
exit $status
