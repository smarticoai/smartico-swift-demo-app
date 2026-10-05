#!/bin/sh
# Builds the demo in Release for the iOS simulator and zips the .app — the
# file attached to a GitHub release ("Try it on the simulator" in the README).
#
#   Tools/make-sim-build.sh
#
# Output: build/SmarticoDemo-simulator.zip (SmarticoDemo.app at its root).
# A simulator build needs no Apple Developer team: it is signed ad hoc.
# The zip opens on the Google sign-in screen.
set -eu

cd "$(dirname "$0")/.."

DERIVED=build/sim-release
APP="$DERIVED/Build/Products/Release-iphonesimulator/SmarticoDemo.app"
ZIP=build/SmarticoDemo-simulator.zip

rm -rf "$DERIVED" "$ZIP"
xcodebuild -project SmarticoDemo.xcodeproj -scheme SmarticoDemo -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$DERIVED" build

if [ ! -d "$APP" ]; then
    echo "error: $APP was not produced" >&2
    exit 1
fi

# --keepParent: the zip holds SmarticoDemo.app itself, so `unzip` yields the bundle.
ditto -c -k --keepParent "$APP" "$ZIP"

echo "built $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '), $(stat -f %z "$ZIP") bytes)"
