#!/bin/sh
# Builds PopFix.app (menu-bar only, no Dock icon).
#   ./build.sh                                   ad-hoc signed, for local use
#   ./build.sh --sign "Developer ID Application: Name (TEAMID)"
#                                                hardened runtime + secure timestamp, zips to PopFix.zip
#   ./build.sh --sign ... --notarize <profile>   also notarizes + staples (profile from `xcrun notarytool store-credentials`)
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
APP=PopFix.app
rm -rf "$APP" PopFix.zip
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PopFix "$APP/Contents/MacOS/PopFix"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
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
</dict></plist>
PL

if [ "$SIGN" = "-" ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  ditto -c -k --keepParent "$APP" PopFix.zip
  if [ -n "$NOTARY" ]; then
    xcrun notarytool submit PopFix.zip --keychain-profile "$NOTARY" --wait
    xcrun stapler staple "$APP"
    rm PopFix.zip; ditto -c -k --keepParent "$APP" PopFix.zip   # re-zip with the stapled ticket
  fi
fi
echo "Built $APP"
