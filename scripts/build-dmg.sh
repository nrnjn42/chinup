#!/bin/bash
set -euo pipefail

# Builds the Mac Catalyst variant. The target is an iOS app (SDKROOT=iphoneos)
# with SUPPORTS_MACCATALYST=YES, so `-destination 'platform=macOS'` is ambiguous
# between "Mac Catalyst" and "Designed for iPad" and must be qualified.

PROJECT_DIR="$(cd "$(dirname "$0")/../src" && pwd)"
BUILD_DIR="$(cd "$(dirname "$0")/.." && pwd)/build"
APP_NAME="ChinUp"
INSTALL=0
MAKE_DMG=1
LOGIN_ITEM=0

for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --no-dmg) MAKE_DMG=0 ;;
    --login-item) INSTALL=1; LOGIN_ITEM=1 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [ -z "${SIGNING_IDENTITY:-}" ]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
    | grep -m1 'Apple Development' \
    | sed -E 's/.*"(.*)"/\1/')"
fi

if [ -z "$SIGNING_IDENTITY" ]; then
  echo "No 'Apple Development' codesigning identity found." >&2
  echo "Set SIGNING_IDENTITY=... or use '-' for ad-hoc signing." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Building $APP_NAME (Release, Mac Catalyst)..."
xcodebuild -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  SYMROOT="$BUILD_DIR" \
  -quiet

APP_PATH="$BUILD_DIR/Release-maccatalyst/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "Error: $APP_PATH not found. Products present:" >&2
  ls "$BUILD_DIR" >&2
  exit 1
fi

echo "Signing with: $SIGNING_IDENTITY"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"

if [ "$INSTALL" -eq 1 ]; then
  echo "Installing to /Applications/$APP_NAME.app..."
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_PATH" "/Applications/$APP_NAME.app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app"
  echo "Installed. Spotlight should find it within a few seconds."
fi

if [ "$LOGIN_ITEM" -eq 1 ]; then
  echo "Registering login item..."
  # Delete first — 'make login item' happily creates duplicates on re-run.
  osascript -e "tell application \"System Events\" to delete (every login item whose name is \"$APP_NAME\")" >/dev/null 2>&1 || true
  osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"/Applications/$APP_NAME.app\", hidden:false}" >/dev/null
  echo "Login items now:"
  osascript -e 'tell application "System Events" to get the name of every login item'
fi

if [ "$MAKE_DMG" -eq 1 ]; then
  echo "Creating DMG..."
  DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
  hdiutil create -volname "$APP_NAME" \
    -srcfolder "$APP_PATH" \
    -ov -format UDZO \
    "$DMG_PATH"
  echo ""
  echo "Done: $DMG_PATH"
  echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
fi
