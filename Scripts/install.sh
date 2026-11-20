#!/bin/zsh
# Builds the app and installs it into /Applications, replacing an older copy.
set -euo pipefail
cd "${0:A:h:h}"
./Scripts/build.sh
osascript -e 'tell application id "com.mihran.PeekBox" to quit' 2>/dev/null || true
rm -rf /Applications/PeekBox.app
ditto PeekBox.app /Applications/PeekBox.app
# Make Finder's "Open With" list and the default-app setting see the installed copy.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for copy in "$PWD/PeekBox.app" build/Build/Products/*/PeekBox.app(N); do
  "$LSREGISTER" -u "$copy" 2>/dev/null || true
done
"$LSREGISTER" -f /Applications/PeekBox.app
print 'Installed: /Applications/PeekBox.app'
