#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p .build/module-cache .build/tmp dist
export TMPDIR="$PWD/.build/tmp/"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
SWIFTC="$(/usr/bin/xcrun --find swiftc)"
SDK="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
ARCH="${VITRA_ARCH:-$(/usr/bin/uname -m)}"
APP="$PWD/dist/Vitra Radio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compilando Vitra Radio para ${ARCH}..."
"$SWIFTC" -parse-as-library -swift-version 5 -O \
    -target "$ARCH-apple-macosx13.0" -sdk "$SDK" \
    -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    Sources/VitraRadio/*.swift -o "$APP/Contents/MacOS/VitraRadio"

"$SWIFTC" -swift-version 5 -sdk "$SDK" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
    scripts/GenerateIcon.swift -o .build/generate-icon
.build/generate-icon "$PWD/.build/AppIcon.iconset"
/usr/bin/iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/Languages"
cp packaging/Languages/*.json "$APP/Contents/Resources/Languages/"
cp packaging/support.json "$APP/Contents/Resources/support.json"
cp packaging/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VITRA_VERSION:-0.1.0}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VITRA_BUILD:-1}" "$APP/Contents/Info.plist"
if [ -n "${VITRA_JAMENDO_CLIENT_ID:-}" ]; then
    /usr/libexec/PlistBuddy -c "Add :JamendoClientID string $VITRA_JAMENDO_CLIENT_ID" "$APP/Contents/Info.plist"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"
/usr/bin/codesign --force --sign - "$APP"
echo "App pronto: $APP"
if [ "${VITRA_SKIP_TESTS:-0}" != "1" ]; then "$APP/Contents/MacOS/VitraRadio" --self-test; fi
