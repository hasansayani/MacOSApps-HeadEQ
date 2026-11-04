#!/bin/zsh
# Builds HeadEQ.app (release) into ./build. Run: ./build_app.sh [--open]
set -euo pipefail
cd "${0:A:h}"

VERSION="$(cat VERSION | tr -d '[:space:]')"
if git rev-parse --git-dir >/dev/null 2>&1 && git rev-parse HEAD >/dev/null 2>&1; then
  BUILD="$(git rev-list --count HEAD)"
  COMMIT="$(git rev-parse --short HEAD)$(git diff --quiet HEAD -- . 2>/dev/null || echo '+')"
else
  BUILD="0"; COMMIT="nogit"
fi

swift build -c release --product HeadEQ
swift build -c release --product make-icon
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/HeadEQ.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/docs"
cp "$BIN_DIR/HeadEQ" "$APP/Contents/MacOS/HeadEQ"

# App icon
ICONSET="build/HeadEQ.iconset"
rm -rf "$ICONSET"
"$BIN_DIR/make-icon" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/HeadEQ.icns"

# Docs
python3 -I tools/md2html.py docs/UserGuide.md "$APP/Contents/Resources/docs/UserGuide.html" "HeadEQ User Guide"
cp docs/*.md CHANGELOG.md "$APP/Contents/Resources/docs/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>HeadEQ</string>
  <key>CFBundleDisplayName</key><string>HeadEQ</string>
  <key>CFBundleIdentifier</key><string>com.headeq.app</string>
  <key>CFBundleExecutable</key><string>HeadEQ</string>
  <key>CFBundleIconFile</key><string>HeadEQ</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>HEQGitCommit</key><string>${COMMIT}</string>
  <key>LSMinimumSystemVersion</key><string>14.2</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 HeadEQ contributors</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>HeadEQ captures system audio so it can apply equalization before it reaches your headphones.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>HeadEQ adjusts the system alert volume when you change it in System Audio.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (sufficient for local use; use a Developer ID to distribute).
codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP — v${VERSION} (${BUILD}) ${COMMIT}"
[[ "${1:-}" == "--open" ]] && open "$APP"
exit 0
