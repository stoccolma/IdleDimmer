#!/bin/sh
# Regenerates IdleDimmer.app/Contents/Resources/AppIcon.icns from tools/make-icon.swift.
set -e
cd "$(dirname "$0")/.."
tmp=$(mktemp -d)
swiftc tools/make-icon.swift -o "$tmp/make-icon"
"$tmp/make-icon" "$tmp/AppIcon.iconset"
mkdir -p IdleDimmer.app/Contents/Resources
iconutil -c icns "$tmp/AppIcon.iconset" -o IdleDimmer.app/Contents/Resources/AppIcon.icns
rm -rf "$tmp"
echo "Wrote IdleDimmer.app/Contents/Resources/AppIcon.icns"
