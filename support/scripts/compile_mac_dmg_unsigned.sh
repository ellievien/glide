#!/usr/bin/env bash
# Builds a DMG of Glide for installing on your own Macs, without an Apple
# Developer account: the app is ad-hoc signed ("Sign to Run Locally") instead of
# with a Developer ID, and not notarized. Gatekeeper therefore refuses a plain
# double-click on any other Mac the first time; the instructions printed at the
# end explain how to allow it. To hand Glide to other people, use
# compile_mac_dmg.sh (Developer ID signing + notarization) instead.
#
# Prerequisites: Xcode, CocoaPods, rustup and fvm (or set FLUTTER to another
# flutter command, e.g. FLUTTER=flutter in CI).
# Run from anywhere; the DMG is written to app/.

set -euo pipefail

FLUTTER="${FLUTTER:-fvm flutter}"
cd "$(dirname "$0")/../.."

VERSION=$(sed -n 's/^version: \([0-9]*\.[0-9]*\.[0-9]*\).*/\1/p' app/pubspec.yaml)
DMG="app/Glide-$VERSION-macos-unsigned.dmg"
APP="app/build/macos/Build/Products/Release/Glide.app"

# The Xcode project signs automatically with team A3K9N976H6. Flutter passes
# FLUTTER_XCODE_* variables to xcodebuild as command-line build settings, which
# take precedence over the project's, so this switches every target to ad-hoc
# signing without touching the project. The hardened runtime only matters for
# notarization, and its library validation would refuse to load the app's own
# ad-hoc signed frameworks, so it is switched off too.
export FLUTTER_XCODE_CODE_SIGN_STYLE=Manual
export FLUTTER_XCODE_CODE_SIGN_IDENTITY=-
export FLUTTER_XCODE_DEVELOPMENT_TEAM=
export FLUTTER_XCODE_PROVISIONING_PROFILE_SPECIFIER=
export FLUTTER_XCODE_ENABLE_HARDENED_RUNTIME=NO

(
  cd app
  $FLUTTER pub get
  $FLUTTER build macos --release
)

echo
echo "Verifying the app's signature..."
if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
  echo
  echo "The built app's signature is invalid. If the repository is on an exFAT or"
  echo "other non-APFS drive, macOS leaves ._* files in the bundle that break it;"
  echo "build from a copy of the repository on the Mac's internal drive."
  exit 1
fi

echo
echo "Creating $DMG..."
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Glide.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname Glide -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"

cat <<EOF

Done: $(pwd)/$DMG

To install on another Mac:
  1. Copy the DMG over (AirDrop works), open it and drag Glide into Applications.
  2. Open Glide once; macOS blocks it because it is not notarized.
     - macOS 15 or later: System Settings > Privacy & Security, scroll down,
       click "Open Anyway" next to Glide, and confirm.
     - macOS 14 or earlier: Control-click Glide in Applications, choose Open,
       then Open again.
     Or, in Terminal: xattr -dr com.apple.quarantine /Applications/Glide.app
  3. Allow local network access when asked, so Glide can find your devices.
EOF
