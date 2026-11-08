#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="截录"
DIST_DIR="$ROOT/dist"
APP="$DIST_DIR/$APP_NAME.app"

echo "==> Building universal release binary"
cd "$ROOT"
swift build -c release --product LongShot --arch arm64 --arch x86_64
BIN_PATH="$(swift build -c release --show-bin-path --arch arm64 --arch x86_64)"
if ! lipo -info "$BIN_PATH/LongShot" | grep -q "x86_64"; then
    echo "error: expected a universal arm64 + x86_64 binary" >&2
    exit 1
fi

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/LongShot" "$APP/Contents/MacOS/LongShot"
chmod 755 "$APP/Contents/MacOS/LongShot"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' 'NR==1 {print $2}')}"
if [[ -n "$IDENTITY" ]]; then
    echo "==> Signing with $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" --timestamp=none "$APP"
else
    echo "==> Signing (ad-hoc)"
    codesign --force --deep --sign - "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ "${1:-}" == "--install" ]]; then
    echo "==> Installing to /Applications"
    osascript -e 'tell application "截录" to quit' >/dev/null 2>&1 || true
    sleep 0.4
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$APP" "/Applications/$APP_NAME.app"
    xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app" 2>/dev/null || true
    echo "Installed /Applications/$APP_NAME.app"
fi

echo "==> Built $APP"
