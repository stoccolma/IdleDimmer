#!/bin/sh
# Builds IdleDimmer.app. Signs with a Developer ID certificate when one is in the
# keychain (or the identity named in SIGN_IDENTITY); otherwise signs ad hoc.
set -e
cd "$(dirname "$0")"
mkdir -p IdleDimmer.app/Contents/MacOS
swiftc -O main.swift -o IdleDimmer.app/Contents/MacOS/IdleDimmer -framework AppKit -framework CoreGraphics -framework AVFoundation
identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)}"
if [ -n "$identity" ]; then
    codesign --force --options runtime --timestamp --entitlements tools/entitlements.plist --sign "$identity" IdleDimmer.app
    echo "Built and signed with: $identity"
else
    codesign --force --sign - IdleDimmer.app
    echo "Built with an ad hoc signature (permissions must be granted again after each rebuild)"
fi
