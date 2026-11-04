#!/bin/zsh
# Release build: sign with Developer ID (hardened runtime), package a DMG,
# notarize with Apple and staple the ticket.
#
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="headeq-notary" \            # created once with: xcrun notarytool store-credentials
#   UPDATE_FEED_URL="https://api.github.com/repos/<you>/headeq/releases/latest" \
#   tools/release.sh
#
#   tools/release.sh --skip-notarize            # local DMG with ad-hoc signing (for testing)
set -euo pipefail
cd "${0:A:h}/.."

SKIP_NOTARIZE=0
[[ "${1:-}" == "--skip-notarize" ]] && SKIP_NOTARIZE=1

UPDATE_FEED_URL="${UPDATE_FEED_URL:-}" ./build_app.sh
APP="build/HeadEQ.app"
VERSION="$(cat VERSION | tr -d '[:space:]')"
DMG="build/HeadEQ-${VERSION}.dmg"

if [[ $SKIP_NOTARIZE == 0 ]]; then
  : "${DEVELOPER_ID:?Set DEVELOPER_ID to your 'Developer ID Application: …' identity}"
  : "${NOTARY_PROFILE:?Set NOTARY_PROFILE (xcrun notarytool store-credentials)}"
  codesign --force --deep --options runtime --timestamp \
    --entitlements tools/HeadEQ.entitlements --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi

rm -f "$DMG"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "HeadEQ ${VERSION}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [[ $SKIP_NOTARIZE == 0 ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi
echo "Release artifact: $DMG"
