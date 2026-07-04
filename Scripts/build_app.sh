#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Lidopen"
EXECUTABLE_NAME="Lidopen"
BUNDLE_ID="utility.lidopen"
BUILD_CONFIG="release"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"
ICONSET_PATH="$OUTPUT_DIR/AppIcon.iconset"
ICNS_PATH="$OUTPUT_DIR/AppIcon.icns"
VERSION_FILE="$ROOT_DIR/VERSION"
APP_VERSION="${LIDOPEN_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
BUILD_NUMBER="${LIDOPEN_BUILD_NUMBER:-1}"
APP_ARCH="${LIDOPEN_ARCH:-$(uname -m)}"
DMG_STAGING_DIR="$OUTPUT_DIR/dmg"
DMG_VOLUME_NAME="$APP_NAME $APP_VERSION"
DMG_PATH="$OUTPUT_DIR/$APP_NAME-$APP_VERSION-macos-$APP_ARCH.dmg"
INSTALL_APP=false
CREATE_DMG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug)
      BUILD_CONFIG="debug"
      shift
      ;;
    --install)
      INSTALL_APP=true
      shift
      ;;
    --dmg|--archive)
      CREATE_DMG=true
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--debug] [--install] [--dmg]" >&2
      exit 1
      ;;
  esac
done

if [[ ! "$APP_VERSION" =~ '^[0-9]+[.][0-9]+[.][0-9]+$' ]]; then
  echo "Invalid app version: $APP_VERSION" >&2
  echo "Expected format: MAJOR.MINOR.PATCH" >&2
  exit 1
fi

if [[ ! "$BUILD_NUMBER" =~ '^[0-9]+$' ]]; then
  echo "Invalid build number: $BUILD_NUMBER" >&2
  echo "Expected a positive integer." >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
rm -rf "$APP_BUNDLE"
rm -rf "$ICONSET_PATH"
rm -rf "$DMG_STAGING_DIR"
rm -rf "$OUTPUT_DIR"/dmg-mount.*(N)
rm -f "$ICNS_PATH"
rm -f "$DMG_PATH"

if [[ -n "${CLANG_MODULE_CACHE_PATH:-}" ]]; then
  mkdir -p "$CLANG_MODULE_CACHE_PATH"
fi

if [[ -n "${SWIFT_MODULE_CACHE_PATH:-}" ]]; then
  mkdir -p "$SWIFT_MODULE_CACHE_PATH"
fi

swift build -c "$BUILD_CONFIG" --package-path "$ROOT_DIR"

swift "$ROOT_DIR/Scripts/generate_icon.swift" "$ICONSET_PATH"
iconutil -c icns "$ICONSET_PATH" -o "$ICNS_PATH"

BUILD_DIR="$(swift build -c "$BUILD_CONFIG" --package-path "$ROOT_DIR" --show-bin-path)"
EXECUTABLE_PATH="$BUILD_DIR/$EXECUTABLE_NAME"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Expected executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

echo "Built app bundle at:"
echo "  $APP_BUNDLE"
echo "Version:"
echo "  $APP_VERSION ($BUILD_NUMBER)"

if [[ "$CREATE_DMG" == true ]]; then
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$APP_BUNDLE" "$DMG_STAGING_DIR/$APP_NAME.app"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"

  hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

  echo "Created DMG at:"
  echo "  $DMG_PATH"
fi

if [[ "$INSTALL_APP" == true ]]; then
  if [[ -d "$INSTALL_PATH" ]]; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true

    for _ in {1..30}; do
      if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        break
      fi
      sleep 0.2
    done

    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
      echo "Refusing to replace $INSTALL_PATH while $APP_NAME is still running." >&2
      echo "Quit the app and run the installer again." >&2
      exit 1
    fi

    rm -rf "$INSTALL_PATH"
  fi

  cp -R "$APP_BUNDLE" "$INSTALL_PATH"
  echo "Installed app at:"
  echo "  $INSTALL_PATH"
fi
