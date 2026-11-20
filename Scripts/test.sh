#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
xcodegen generate --quiet
xcodebuild -quiet -project PeekBox.xcodeproj -scheme PeekBox -destination 'platform=macOS' -derivedDataPath build test
