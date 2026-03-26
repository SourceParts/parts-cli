#!/bin/bash
set -e

cd "$(dirname "$0")"

swift build "$@"

BINARY="$(swift build --show-bin-path)/PartsStudio"
BIN_DIR="$(dirname "$BINARY")"
ENTITLEMENTS="$(dirname "$0")/PartsStudio.entitlements"

# Copy icon next to binary so SplashView and NSApp icon can find it
ICON_SRC="$(dirname "$0")/PartsStudio.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$BIN_DIR/PartsStudio.icns"
fi

codesign --force --sign - "$BINARY" 2>/dev/null
echo "Signed: $BINARY"
