#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate --quiet
xcodebuild -quiet -project PeekBox.xcodeproj -scheme PeekBox -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build build
ditto build/Build/Products/Release/PeekBox.app PeekBox.app
codesign --verify --deep --strict PeekBox.app
print 'Done: PeekBox.app'
