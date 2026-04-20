#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="${APP_NAME:-langx}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-langx}"
BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-dev.langx.app}"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD="${APP_BUILD:-1}"
MIN_SYSTEM_VERSION="${MIN_SYSTEM_VERSION:-14.0}"
VOL_NAME="${VOL_NAME:-$APP_DISPLAY_NAME}"

if [[ -z "${BUILD_DIR:-}" ]]; then
    if [[ "${SKIP_BUILD:-0}" == "1" ]]; then
        echo "BUILD_DIR must be set when SKIP_BUILD=1" >&2
        exit 1
    fi

    cd "$REPO_ROOT"
    swift build -c release
    BUILD_DIR="$(swift build -c release --show-bin-path)"
fi

EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLE_PATH="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"

DIST_DIR="$REPO_ROOT/dist"
WORK_DIR="$REPO_ROOT/.build/dmg"
STAGING_DIR="$WORK_DIR/staging"
DIST_APP_BUNDLE_PATH="$DIST_DIR/$APP_DISPLAY_NAME.app"
APP_BUNDLE_PATH="$STAGING_DIR/$APP_DISPLAY_NAME.app"
DMG_PATH="$DIST_DIR/${APP_NAME}-${APP_VERSION}.dmg"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
    echo "Missing executable at $EXECUTABLE_PATH" >&2
    exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
    echo "Missing resource bundle at $RESOURCE_BUNDLE_PATH" >&2
    exit 1
fi

rm -rf "$WORK_DIR"
rm -rf "$DIST_APP_BUNDLE_PATH"
mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS" "$DIST_DIR"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME"
cp -R "$RESOURCE_BUNDLE_PATH" "$APP_BUNDLE_PATH/${APP_NAME}_${APP_NAME}.bundle"

/usr/bin/plutil -create xml1 "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_IDENTIFIER" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_DISPLAY_NAME" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_BUILD" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MIN_SYSTEM_VERSION" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$APP_BUNDLE_PATH/Contents/Info.plist"

cp -R "$APP_BUNDLE_PATH" "$DIST_APP_BUNDLE_PATH"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "Created app bundle: $DIST_APP_BUNDLE_PATH"
echo "Created DMG: $DMG_PATH"
