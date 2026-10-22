#!/bin/zsh
# Builds Revive in Release and packages it as a drag-to-install disk image.
#
#   scripts/make-dmg.sh                                  # ad-hoc signature (for anyone, no certificate needed)
#   SIGN_IDENTITY="Revive Release" scripts/make-dmg.sh   # the maintainer's release certificate (see RELEASING.md)
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=revive scripts/make-dmg.sh
#
# A stable certificate (SIGN_IDENTITY or DEVELOPER_ID) keeps the app's identity across versions,
# so macOS keeps Full Disk Access after an update. With DEVELOPER_ID and NOTARY_PROFILE
# (see `xcrun notarytool store-credentials`), the DMG is also notarized and stapled.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=build/release
DMG="build/Revive-$VERSION.dmg"

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

# Ad-hoc unless an identity is given, whatever Config/Local.xcconfig says.
SIGNING=(CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="")
DMG_IDENTITY=""
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  TEAM=$(echo "$DEVELOPER_ID" | sed -E 's/.*\(([A-Z0-9]+)\).*/\1/')
  SIGNING=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM" OTHER_CODE_SIGN_FLAGS="--timestamp")
  DMG_IDENTITY="$DEVELOPER_ID"
elif [[ -n "${SIGN_IDENTITY:-}" ]]; then
  # No Team ID: the app needs to load Sparkle without library validation (see the entitlements file).
  SIGNING=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" REVIVE_ENTITLEMENTS=App/Revive-SelfSigned.entitlements)
  DMG_IDENTITY="$SIGN_IDENTITY"
fi

xcodebuild -project Revive.xcodeproj -scheme Revive -configuration Release -derivedDataPath "$BUILD" "${SIGNING[@]}" build | tail -1
APP="$BUILD/Build/Products/Release/Revive.app"
codesign --verify --deep --strict "$APP"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Revive $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1
rm -rf "$STAGE"

if [[ -n "$DMG_IDENTITY" ]]; then
  codesign --sign "$DMG_IDENTITY" "$DMG"
fi
if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

shasum -a 256 "$DMG"
echo "Created $DMG"
