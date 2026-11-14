#!/bin/sh
# Builds a notarized IdleDimmer-<version>.zip that opens without a Gatekeeper warning.
# One-time setup: xcrun notarytool store-credentials IdleDimmer
set -e
cd "$(dirname "$0")/.."
profile="${NOTARY_PROFILE:-IdleDimmer}"
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" IdleDimmer.app/Contents/Info.plist)
zip="IdleDimmer-$version.zip"
./build.sh
codesign -dv IdleDimmer.app 2>&1 | grep -q "Authority=Developer ID Application" || codesign -dvv IdleDimmer.app 2>&1 | grep -q "Developer ID Application" || { echo "Not signed with a Developer ID certificate; cannot notarize."; exit 1; }
rm -f "$zip"
ditto -c -k --keepParent IdleDimmer.app "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$profile" --wait
xcrun stapler staple IdleDimmer.app
rm -f "$zip"
ditto -c -k --keepParent IdleDimmer.app "$zip"
spctl -a -vv IdleDimmer.app
echo "Ready: $zip"
