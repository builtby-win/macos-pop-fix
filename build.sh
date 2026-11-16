#!/bin/sh
# Builds PopFix.app (menu-bar only, no Dock icon).
#   ./build.sh                                   ad-hoc signed, for local use
#   ./build.sh --sign "Developer ID Application: Name (TEAMID)"
#                                                hardened runtime + secure timestamp, zips to PopFix.zip
#   ./build.sh --sign ... --notarize <profile>   also notarizes + staples (profile from `xcrun notarytool store-credentials`)
# Signed builds also produce PopFix.dmg (drag-to-Applications) and refresh appcast.xml for Sparkle
# (EdDSA key is read from the login keychain; see `generate_keys`).
set -e
cd "$(dirname "$0")"
SIGN="-"; NOTARY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --sign) SIGN="$2"; shift 2 ;;
    --notarize) NOTARY="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

swift build -c release
swift build -c release --product MediaRemoteAdapter
APP=PopFix.app
rm -rf "$APP" PopFix.zip PopFix.dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/PopFix "$APP/Contents/MacOS/PopFix"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/PopFix"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Now Playing bridge: perl loads this dylib and runs run.pl (see NowPlaying in main.swift).
cp .build/release/libMediaRemoteAdapter.dylib "$APP/Contents/Frameworks/"
cp .build/checkouts/mediaremote-adapter/Sources/MediaRemoteAdapter/Resources/run.pl "$APP/Contents/Resources/"
cp .build/checkouts/mediaremote-adapter/LICENSE "$APP/Contents/Resources/mediaremote-adapter-LICENSE.txt"
cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt"
VERSION=$(cat VERSION)
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>win.builtby.popfix</string>
<key>CFBundleName</key><string>PopFix</string>
<key>CFBundleDisplayName</key><string>PopFix</string>
<key>CFBundleExecutable</key><string>PopFix</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>SUEnableAutomaticChecks</key><true/>
<key>SUFeedURL</key><string>https://raw.githubusercontent.com/builtby-win/macos-pop-fix/main/appcast.xml</string>
<key>SUPublicEDKey</key><string>HYJ7dSy4TGt+Tw3oog+HO3ozMwjB9CybsytpNK8C6OQ=</string>
</dict></plist>
PL

if [ "$SIGN" = "-" ]; then
  codesign --force --deep --sign - "$APP"
else
  SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
  for x in "$SPK/XPCServices/Installer.xpc" "$SPK/XPCServices/Downloader.xpc" "$SPK/Autoupdate" "$SPK/Updater.app" "$APP/Contents/Frameworks/Sparkle.framework" "$APP/Contents/Frameworks/libMediaRemoteAdapter.dylib" "$APP"; do
    codesign --force --options runtime --timestamp --sign "$SIGN" "$x"
  done
  codesign --verify --strict --deep --verbose=2 "$APP"
  notarize() { xcrun notarytool submit "$1" --keychain-profile "$NOTARY" --wait; }
  if [ -n "$NOTARY" ]; then
    ditto -c -k --keepParent "$APP" PopFix.zip; notarize PopFix.zip
    xcrun stapler staple "$APP"
  fi
  ditto -c -k --keepParent "$APP" PopFix.zip   # (re-)zip with the stapled ticket
  # DMG: app + /Applications symlink for drag-install.
  STAGE=$(mktemp -d); cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname PopFix -srcfolder "$STAGE" -ov -format UDZO PopFix.dmg >/dev/null; rm -rf "$STAGE"
  codesign --force --timestamp --sign "$SIGN" PopFix.dmg
  if [ -n "$NOTARY" ]; then notarize PopFix.dmg; xcrun stapler staple PopFix.dmg; fi
  # Sparkle appcast: points at the GitHub release asset for this version.
  FEED=$(mktemp -d); cp PopFix.zip "$FEED/PopFix-$VERSION.zip"; [ -f appcast.xml ] && cp appcast.xml "$FEED/"
  .build/artifacts/sparkle/Sparkle/bin/generate_appcast --download-url-prefix "https://github.com/builtby-win/macos-pop-fix/releases/download/v$VERSION/" "$FEED"
  cp "$FEED/appcast.xml" appcast.xml; rm -rf "$FEED"
fi
echo "Built $APP"
