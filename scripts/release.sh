#!/bin/zsh
# Publishes a new version of Revive in one command:
#
#   scripts/release.sh 0.4.1 notes.md
#
# 1. bumps the version and build number in project.yml
# 2. builds and signs the DMG with the release certificate (SIGN_IDENTITY, default "Revive Release")
# 3. signs the DMG for Sparkle with the EdDSA key in the maintainer's keychain
# 4. adds the version to appcast.xml, which every installed copy checks for updates
# 5. commits, tags, pushes and creates the GitHub release with the DMG
#
# LOCAL=1 stops after step 4 and points the appcast at DOWNLOAD_BASE (for testing updates locally).
# See RELEASING.md for the one-time setup.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version> [notes.md]}
NOTES=${2:-}
SIGN_IDENTITY=${SIGN_IDENTITY:-"Revive Release"}
SPARKLE_VERSION=2.10.0
SPARKLE_BIN=build/sparkle/bin
KEY_ACCOUNT=io.github.mbielle.Revive
LOCAL=${LOCAL:-0}
DOWNLOAD_BASE=${DOWNLOAD_BASE:-https://github.com/mbielle/revive/releases/download/v$VERSION}

if [[ "$LOCAL" != 1 && -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first."; exit 1
fi
security find-identity -p codesigning | grep -q "\"$SIGN_IDENTITY\"" || { echo "Signing identity \"$SIGN_IDENTITY\" not found (see RELEASING.md)."; exit 1; }

# Sparkle's command line tools, downloaded once from its official release.
if [[ ! -x "$SPARKLE_BIN/sign_update" ]]; then
  mkdir -p build/sparkle
  gh release download "$SPARKLE_VERSION" --repo sparkle-project/Sparkle --pattern "Sparkle-$SPARKLE_VERSION.tar.xz" --dir build/sparkle --clobber
  tar -xf "build/sparkle/Sparkle-$SPARKLE_VERSION.tar.xz" -C build/sparkle
fi

# 1. Version and build number (the build number always increases: Sparkle compares it).
CURRENT_BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed -E 's/[^0-9]*([0-9]+).*/\1/')
BUILD_NUMBER=$((CURRENT_BUILD + 1))
sed -i '' -E "s/(MARKETING_VERSION: )\"[^\"]+\"/\1\"$VERSION\"/" project.yml
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"[^\"]+\"/\1\"$BUILD_NUMBER\"/" project.yml
echo "Building Revive $VERSION ($BUILD_NUMBER)…"

# 2. Signed DMG.
SIGN_IDENTITY="$SIGN_IDENTITY" scripts/make-dmg.sh
DMG="build/Revive-$VERSION.dmg"

# 3. Sparkle signature: prints  sparkle:edSignature="…" length="…"
SPARKLE_SIGNATURE=$("$SPARKLE_BIN/sign_update" --account "$KEY_ACCOUNT" "$DMG")

# 4. Appcast.
python3 scripts/update_appcast.py appcast.xml "$VERSION" "$BUILD_NUMBER" "$DOWNLOAD_BASE/Revive-$VERSION.dmg" "$SPARKLE_SIGNATURE" "$NOTES"
echo "appcast.xml updated."

if [[ "$LOCAL" == 1 ]]; then
  echo "LOCAL=1: nothing committed or published. DMG: $DMG"
  exit 0
fi

# 5. Publish.
git add project.yml appcast.xml
git commit -q -m "Release v$VERSION"
git tag -a "v$VERSION" -m "Revive $VERSION"
git push -q origin main "v$VERSION"
NOTE_ARGS=(--generate-notes)
[[ -n "$NOTES" ]] && NOTE_ARGS=(--notes-file "$NOTES")
gh release create "v$VERSION" "$DMG" --title "Revive $VERSION" --prerelease "${NOTE_ARGS[@]}"
echo "Revive $VERSION is out. Installed copies will offer it within an hour."
