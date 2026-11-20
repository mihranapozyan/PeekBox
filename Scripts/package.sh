#!/bin/zsh
# Tests, builds the app and packs it into dist/PeekBox-<version>.zip with a SHA-256 checksum.
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/test.sh
./Scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' PeekBox.app/Contents/Info.plist)
mkdir -p dist
archive="dist/PeekBox-$version.zip"
rm -f "$archive" "$archive.sha256"
ditto -c -k --keepParent PeekBox.app "$archive"
(cd dist && shasum -a 256 "PeekBox-$version.zip" > "PeekBox-$version.zip.sha256")
print "Done: $archive"
