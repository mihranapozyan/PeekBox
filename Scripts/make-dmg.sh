#!/bin/zsh
# Builds the app and packs it into dist/PeekBox.dmg: the app next to an Applications shortcut, ready to drag.
# The release asset keeps the plain name "PeekBox.dmg" so the README's download link always points at the latest one.
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' PeekBox.app/Contents/Info.plist)
stage=build/dmg
rw=build/PeekBox-rw.dmg
mkdir -p dist
rm -rf "$stage" "$rw" dist/PeekBox.dmg
mkdir -p "$stage"
ditto PeekBox.app "$stage/PeekBox.app"
ln -s /Applications "$stage/Applications"

# Writable image first, so Finder can store the window layout; then compress.
hdiutil create -quiet -volname PeekBox -srcfolder "$stage" -fs HFS+ -format UDRW -ov "$rw"
# Another "PeekBox" volume may already be mounted, so address this one by its real mount point ("PeekBox 1", …).
attached=$(hdiutil attach -readwrite -noverify -noautoopen "$rw" | awk -F'\t' '/\/Volumes\// {print $1 "|" $NF; exit}')
device=$(print -r -- "${attached%%|*}" | xargs)
volume=$(basename "${attached##*|}")
osascript - "$volume" <<'APPLESCRIPT' || print "Finder layout skipped (Automation permission not granted)"
on run argv
set volumeName to item 1 of argv
tell application "Finder"
    tell disk volumeName
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 740, 560}
        set viewOptions to icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set position of item "PeekBox.app" of container window to {140, 170}
        set position of item "Applications" of container window to {400, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
end run
APPLESCRIPT
[[ -f "/Volumes/$volume/.DS_Store" ]] && print "Finder layout saved" || print "Finder layout not saved"
sync
hdiutil detach -quiet "$device"
hdiutil convert -quiet "$rw" -format UDZO -imagekey zlib-level=9 -o dist/PeekBox.dmg
rm -f "$rw"
(cd dist && shasum -a 256 PeekBox.dmg > PeekBox.dmg.sha256)
print "Done: dist/PeekBox.dmg ($version)"
