#!/bin/sh
# Prints the build number (CFBundleVersion) for an App Store Connect upload:
# the current UTC time as YYYYMMDDHHMM, e.g. 202610181430.
#
# It always increases, needs no App Store Connect API, and is far above the
# builds already uploaded (3 at most). Two uploads in the same minute get the
# same number, and App Store Connect rejects the second.
#
# Used by the fastlane beta and release lanes and by CI. Every target gets it
# through the CURRENT_PROJECT_VERSION build setting, so the app and the widget
# extension always match.
set -eu
date -u +%Y%m%d%H%M
