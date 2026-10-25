#!/bin/sh
set -e

echo "Installing XcodeGen..."
brew install xcodegen

echo "Generating Xcode project from project.yml..."
"$CI_PRIMARY_REPOSITORY_PATH/ci_scripts/generate_project.sh"

echo "Project generated successfully."
