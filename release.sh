#!/bin/sh
# Ships the version in VERSION: signed+notarized build, GitHub release assets, then the Sparkle appcast on main.
# Order matters: appcast.xml must only reach main after the assets it points at exist.
#   ./release.sh "<Developer ID identity>" <notarytool-profile> "<release notes>"
set -e
cd "$(dirname "$0")"
[ $# -eq 3 ] || { echo "usage: $0 <identity> <notary-profile> <notes>" >&2; exit 2; }
V=$(cat VERSION); TAG="v$V"; REPO=builtby-win/macos-pop-fix
[ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "commit your changes first" >&2; exit 1; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD must be pushed to origin/main (git fetch; push first)" >&2; exit 1; }

./build.sh --sign "$1" --notarize "$2"
cp PopFix.zip "PopFix-$V.zip"
gh release create "$TAG" PopFix.dmg PopFix.zip "PopFix-$V.zip" -R "$REPO" -t "PopFix $V" -n "$3" --target "$(git rev-parse HEAD)"

git add appcast.xml
git commit -m "chore(release): appcast for $V"
git push origin HEAD:main

# Verify the live feed: lists this version, enclosure downloads, EdDSA signature checks out (raw CDN can lag ~1 min).
FEED=https://raw.githubusercontent.com/$REPO/main/appcast.xml
for _ in 1 2 3 4 5 6 7 8 9 10; do curl -fsSL "$FEED" | grep -q "shortVersionString>$V<" && break; sleep 15; done
curl -fsSL "$FEED" > /tmp/popfix-feed.xml
grep -q "shortVersionString>$V<" /tmp/popfix-feed.xml || { echo "feed does not list $V" >&2; exit 1; }
URL=$(grep -o 'url="[^"]*"' /tmp/popfix-feed.xml | tail -1 | cut -d'"' -f2)
SIG=$(grep -o 'edSignature="[^"]*"' /tmp/popfix-feed.xml | tail -1 | cut -d'"' -f2)
curl -fsSL -o /tmp/popfix-dl.zip "$URL"
.build/artifacts/sparkle/Sparkle/bin/sign_update --verify /tmp/popfix-dl.zip "$SIG"
rm -f /tmp/popfix-dl.zip /tmp/popfix-feed.xml "PopFix-$V.zip"
echo "Released $V; feed verified."
