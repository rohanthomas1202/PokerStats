#!/bin/sh
# Prints the build number (CFBundleVersion) for an App Store Connect upload:
# the current UTC time as YYYYMMDDHHMMSS, e.g. 20261018143005.
#
# It always increases, needs no App Store Connect API, and fits the
# 18-character CFBundleVersion limit. Two uploads only collide if they start
# in the same second. A 14-digit number is higher than any 12-digit
# YYYYMMDDHHMM build from the earlier format, so the switch is safe.
#
# A version can't go back to a smaller counter: once a timestamp build is
# uploaded for a version, every later build of that version must be higher.
# Any other upload path (Xcode Cloud, #66) must use this script or start
# above the latest timestamp build.
#
# Used by the fastlane beta and release lanes and by CI. Every target gets it
# through the CURRENT_PROJECT_VERSION build setting, so the app and its
# extensions always match.
set -eu
date -u +%Y%m%d%H%M%S
