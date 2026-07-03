#!/bin/zsh
# Builds a universal (Apple Silicon + Intel) Ledge.app into dist/
set -e
cd "$(dirname "$0")"

swift build -c release --arch arm64 --arch x86_64

BIN=".build/apple/Products/Release/Ledge"
if [[ ! -f "$BIN" ]]; then
  BIN=".build/release/Ledge"
fi

APP="dist/Ledge.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Ledge"
cp Info.plist "$APP/Contents/Info.plist"
cp Ledge.icns "$APP/Contents/Resources/Ledge.icns"
codesign --force -s - "$APP"

# Nudge Finder/LaunchServices so the icon is picked up immediately instead of
# showing a stale or generic icon from a previous iconless build.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

echo "Built $APP"
lipo -archs "$APP/Contents/MacOS/Ledge" 2>/dev/null || true
echo "Run it with: open $APP"
