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
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
CODESIGN_DMG_IDENTITY="${CODESIGN_DMG_IDENTITY:-$CODESIGN_IDENTITY}"
CODESIGN_TIMESTAMP="${CODESIGN_TIMESTAMP:-0}"
ENABLE_HARDENED_RUNTIME="${ENABLE_HARDENED_RUNTIME:-1}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
STAPLE="${STAPLE:-$NOTARIZE}"

log() {
    echo "==> $*"
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

sign_target() {
    local target_path="$1"
    local identity="$2"
    local target_kind="$3"
    local -a args

    args=(--force --sign "$identity")
    if [[ "$CODESIGN_TIMESTAMP" == "1" ]]; then
        args+=(--timestamp)
    else
        args+=(--timestamp=none)
    fi

    if [[ "$target_kind" == "app" && "$ENABLE_HARDENED_RUNTIME" == "1" ]]; then
        args+=(--options runtime)
    fi

    log "Signing $target_kind: $target_path"
    codesign "${args[@]}" "$target_path"
}

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
ICON_GENERATOR_PATH="$WORK_DIR/generate-app-icon"
ICON_WORK_DIR="$WORK_DIR/icon"
ICON_FILE_PATH="$ICON_WORK_DIR/AppIcon.icns"

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
mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS" "$APP_BUNDLE_PATH/Contents/Resources" "$DIST_DIR"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE_PATH/Contents/MacOS/$APP_NAME"
ditto "$RESOURCE_BUNDLE_PATH" "$APP_BUNDLE_PATH/${APP_NAME}_${APP_NAME}.bundle"

log "Generating application icon"
swiftc \
    -o "$ICON_GENERATOR_PATH" \
    "$REPO_ROOT/Sources/langx/AppIcon.swift" \
    "$REPO_ROOT/scripts/generate-app-icon.swift"
"$ICON_GENERATOR_PATH" "$ICON_WORK_DIR"
cp "$ICON_FILE_PATH" "$APP_BUNDLE_PATH/Contents/Resources/AppIcon.icns"

/usr/bin/plutil -create xml1 "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $APP_NAME" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_IDENTIFIER" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_DISPLAY_NAME" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $APP_VERSION" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $APP_BUILD" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string $MIN_SYSTEM_VERSION" "$APP_BUNDLE_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$APP_BUNDLE_PATH/Contents/Info.plist"

if [[ -n "$CODESIGN_IDENTITY" ]]; then
    require_command codesign
    sign_target "$APP_BUNDLE_PATH" "$CODESIGN_IDENTITY" app
    log "Verifying app signature"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE_PATH"
else
    log "Skipping app signing because CODESIGN_IDENTITY is not set"
fi

ditto "$APP_BUNDLE_PATH" "$DIST_APP_BUNDLE_PATH"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

log "Creating DMG: $DMG_PATH"
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ -n "$CODESIGN_DMG_IDENTITY" ]]; then
    require_command codesign
    sign_target "$DMG_PATH" "$CODESIGN_DMG_IDENTITY" dmg
    log "Verifying DMG signature"
    codesign --verify --verbose=2 "$DMG_PATH"
else
    log "Skipping DMG signing because CODESIGN_DMG_IDENTITY is not set"
fi

if [[ "$NOTARIZE" == "1" ]]; then
    if [[ -z "$NOTARY_PROFILE" ]]; then
        echo "NOTARY_PROFILE must be set when NOTARIZE=1" >&2
        exit 1
    fi
    if [[ -z "$CODESIGN_IDENTITY" ]]; then
        echo "CODESIGN_IDENTITY must be set when NOTARIZE=1" >&2
        exit 1
    fi

    require_command xcrun
    log "Submitting DMG for notarization with profile: $NOTARY_PROFILE"
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
fi

if [[ "$STAPLE" == "1" ]]; then
    require_command xcrun
    log "Stapling notarization ticket to DMG"
    xcrun stapler staple "$DMG_PATH"
fi

echo "Created app bundle: $DIST_APP_BUNDLE_PATH"
echo "Created DMG: $DMG_PATH"
