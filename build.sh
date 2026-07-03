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

echo "Built $APP"
lipo -archs "$APP/Contents/MacOS/Ledge" 2>/dev/null || true
echo "Run it with: open $APP"
