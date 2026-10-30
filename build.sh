#!/bin/sh
# Builds PopFix.app (menu-bar only, no Dock icon).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=PopFix.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/PopFix "$APP/Contents/MacOS/PopFix"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>win.builtby.popfix</string>
<key>CFBundleName</key><string>PopFix</string>
<key>CFBundleExecutable</key><string>PopFix</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
</dict></plist>
PL
codesign --force --sign - "$APP"
echo "Built $APP"
