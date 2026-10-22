#!/bin/zsh
# Builds Revive in Release and packages it as a drag-to-install disk image.
#
#   scripts/make-dmg.sh                    # unsigned build (users must right-click › Open the first time)
#   DEVELOPER_ID="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=revive scripts/make-dmg.sh
#
# With DEVELOPER_ID set, the app, its helper and the DMG are signed with the hardened runtime.
# With NOTARY_PROFILE set too (see `xcrun notarytool store-credentials`), the DMG is notarized and stapled.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=build/release
DMG="build/Revive-$VERSION.dmg"

command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen"; exit 1; }
xcodegen generate --quiet

# Ad-hoc unless a Developer ID is given, whatever Config/Local.xcconfig says.
SIGNING=(CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="")
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  TEAM=$(echo "$DEVELOPER_ID" | sed -E 's/.*\(([A-Z0-9]+)\).*/\1/')
  SIGNING=(CODE_SIGN_IDENTITY="$DEVELOPER_ID" DEVELOPMENT_TEAM="$TEAM" OTHER_CODE_SIGN_FLAGS="--timestamp")
fi

xcodebuild -project Revive.xcodeproj -scheme Revive -configuration Release -derivedDataPath "$BUILD" "${SIGNING[@]}" build | tail -1
APP="$BUILD/Build/Products/Release/Revive.app"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "Revive $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --sign "$DEVELOPER_ID" --timestamp "$DMG"
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

shasum -a 256 "$DMG"
echo "Created $DMG"
