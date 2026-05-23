#!/usr/bin/env bash
#
# build-app.sh — Build OpenType.app and (optionally) package it as a DMG.
#
# Uses xcodebuild (not bare swift build) so that Metal shaders required
# by mlx-swift are compiled into default.metallib.
#
# Usage:
#   ./scripts/build-app.sh              # build .app + .dmg
#   ./scripts/build-app.sh --app-only   # build .app only
#   ./scripts/build-app.sh --help       # show help
#
# Requirements:
#   - macOS with Xcode (full install, not just CLI tools)
#   - Swift 6.0+
#

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────────

APP_NAME="OpenType"
BUNDLE_ID="com.opentype.voiceinput"
# Default: use latest git tag (strip leading "v"), fallback to 0.0.0-dev
if [ -z "${VERSION:-}" ]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0-dev")"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

DERIVED_DATA="${PROJECT_DIR}/.build/xcode"
BUILD_DIR="${DERIVED_DATA}/Build/Products/Release"
DIST_DIR="${PROJECT_DIR}/dist"
APP_ONLY=false
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

# ─── Parse arguments ────────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --app-only)  APP_ONLY=true ;;
        --version=*) VERSION="${arg#*=}" ;;
        --sign=*)    SIGN_IDENTITY="${arg#*=}" ;;
        --help|-h)
            echo "Usage: $0 [--version=X.Y.Z] [--app-only] [--sign=IDENTITY] [--help]"
            echo ""
            echo "  --version=X.Y.Z    Set version (default: latest git tag, or \$VERSION env)"
            echo "  --app-only         Build .app bundle only, skip DMG creation"
            echo "  --sign=IDENTITY    Code signing identity (default: auto-detect)"
            echo "                     Use '--sign=-' to force ad-hoc signing"
            echo "  --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"

# ─── Helpers ────────────────────────────────────────────────────────────────────

step() { echo ""; echo "▶ $1"; }
done_msg() { echo "  ✓ $1"; }

# ─── Step 1: Build with xcodebuild (Universal Binary) ─────────────────────────

step "Building ${APP_NAME} (Release, arm64)…"
cd "${PROJECT_DIR}"
xcodebuild \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -derivedDataPath "${DERIVED_DATA}" \
    -destination 'platform=macOS' \
    ARCHS="arm64" \
    ONLY_ACTIVE_ARCH=NO \
    build \
    -quiet
done_msg "Build succeeded"

step "Building OpenType CLI helper (Release, arm64)…"
swift build -c release --product OpenTypeCLI --arch arm64
CLI_BUILD_DIR="$(swift build -c release --product OpenTypeCLI --arch arm64 --show-bin-path)"
done_msg "CLI helper built"

# ─── Step 2: Assemble .app bundle ───────────────────────────────────────────────

step "Assembling ${APP_NAME}.app…"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Binary
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "${CLI_BUILD_DIR}/OpenTypeCLI" "${APP_BUNDLE}/Contents/MacOS/opentype"

# Info.plist (with version injected)
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}"           "${APP_BUNDLE}/Contents/Info.plist"

# PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# Copy ALL resource bundles produced by xcodebuild (includes Metal shaders)
for bundle in "${BUILD_DIR}"/*.bundle; do
    [ -d "$bundle" ] || continue
    cp -R "$bundle" "${APP_BUNDLE}/Contents/Resources/"
done

done_msg "App bundle assembled"

# ─── Step 3: Build AppIcon asset catalog (light + dark variants) ────────────────

step "Building AppIcon asset catalog (light + dark variants)…"

ICON_RESOURCE_DIR="${PROJECT_DIR}/Sources/Resources"
ICON_WORK_DIR="${PROJECT_DIR}/.build/AppIcon.work"
ICONSET_DIR="${ICON_WORK_DIR}/Assets.xcassets/AppIcon.appiconset"
ACTOOL_OUT_DIR="${ICON_WORK_DIR}/compiled"

rm -rf "${ICON_WORK_DIR}"
mkdir -p "${ICONSET_DIR}" "${ACTOOL_OUT_DIR}"

# Generate sized PNGs for both appearances; write Contents.json with
# `luminosity = dark` variants so macOS Sonoma+ swaps the Launchpad/Dock
# icon based on system appearance.
SIZE_SPECS=(
    "16:16:1x"  "16:32:2x"
    "32:32:1x"  "32:64:2x"
    "128:128:1x" "128:256:2x"
    "256:256:1x" "256:512:2x"
    "512:512:1x" "512:1024:2x"
)

CONTENTS_JSON="${ICONSET_DIR}/Contents.json"
{
    echo '{'
    echo '  "images" : ['
    first=true
    for spec in "${SIZE_SPECS[@]}"; do
        pt="${spec%%:*}"
        rest="${spec#*:}"
        px="${rest%%:*}"
        scale="${rest##*:}"
        light_name="icon_${pt}x${pt}_${scale}.png"
        dark_name="icon_${pt}x${pt}_${scale}_dark.png"

        sips -z "${px}" "${px}" "${ICON_RESOURCE_DIR}/AppIconLight.png" \
            --out "${ICONSET_DIR}/${light_name}" >/dev/null
        sips -z "${px}" "${px}" "${ICON_RESOURCE_DIR}/AppIconDark.png" \
            --out "${ICONSET_DIR}/${dark_name}" >/dev/null

        if [ "$first" = true ]; then first=false; else echo '    ,'; fi
        cat <<EOF
    {
      "idiom" : "mac",
      "scale" : "${scale}",
      "size" : "${pt}x${pt}",
      "filename" : "${light_name}"
    },
    {
      "idiom" : "mac",
      "scale" : "${scale}",
      "size" : "${pt}x${pt}",
      "filename" : "${dark_name}",
      "appearances" : [
        { "appearance" : "luminosity", "value" : "dark" }
      ]
    }
EOF
    done
    echo '  ],'
    echo '  "info" : { "version" : 1, "author" : "opentype" }'
    echo '}'
} > "${CONTENTS_JSON}"

xcrun actool "${ICON_WORK_DIR}/Assets.xcassets" \
    --compile "${ACTOOL_OUT_DIR}" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --include-all-app-icons \
    --output-partial-info-plist "${ICON_WORK_DIR}/Assets-partial.plist" \
    --output-format human-readable-text \
    >/dev/null

cp "${ACTOOL_OUT_DIR}/Assets.car" "${APP_BUNDLE}/Contents/Resources/"

# Keep .icns files for Finder/LaunchServices fallback and for the in-app
# preview in AboutView/SettingsView, which read these via Bundle. Finder still
# resolves CFBundleIconFile through AppIcon.icns, so keep the neutral fallback
# on the dark artwork instead of the white light-mode tile.
cp "${ICON_RESOURCE_DIR}/AppIconDark.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cp "${ICON_RESOURCE_DIR}/AppIconLight.icns" "${APP_BUNDLE}/Contents/Resources/AppIconLight.icns"
cp "${ICON_RESOURCE_DIR}/AppIconDark.icns" "${APP_BUNDLE}/Contents/Resources/AppIconDark.icns"
done_msg "AppIcon compiled to Assets.car (light + dark)"

# ─── Step 4: Code sign ───────────────────────────────────────────────────────

step "Code signing (hardened runtime + entitlements)…"

ENTITLEMENTS="${PROJECT_DIR}/Resources/OpenType.entitlements"

if [ -z "$SIGN_IDENTITY" ]; then
    for candidate in "Developer ID Application" "Apple Development" "OpenType Signing"; do
        if security find-identity -v -p codesigning 2>/dev/null | grep -q "$candidate"; then
            SIGN_IDENTITY="$candidate"
            break
        fi
    done
fi

SIGN_FLAGS=(--force --deep --options runtime --entitlements "$ENTITLEMENTS")

if [ -n "$SIGN_IDENTITY" ] && [ "$SIGN_IDENTITY" != "-" ]; then
    codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "${APP_BUNDLE}"
    done_msg "Signed with: $SIGN_IDENTITY (hardened runtime)"
else
    codesign "${SIGN_FLAGS[@]}" --sign - "${APP_BUNDLE}"
    done_msg "Signed (ad-hoc, hardened runtime)"
    echo "  ⚠ Ad-hoc signing: first launch on other machines may require:"
    echo "    xattr -cr OpenType.app"
fi

# ─── Step 5: Create DMG ────────────────────────────────────────────────────────

if [ "$APP_ONLY" = true ]; then
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo "  Done!  ${APP_BUNDLE}"
    echo "═══════════════════════════════════════════════════"
    exit 0
fi

step "Creating DMG…"

rm -f "${DMG_PATH}"

DMG_TMP="${DIST_DIR}/.dmg-staging"
rm -rf "${DMG_TMP}"
mkdir -p "${DMG_TMP}"

cp -R "${APP_BUNDLE}" "${DMG_TMP}/"
ln -s /Applications "${DMG_TMP}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_TMP}" \
    -ov -format UDZO \
    "${DMG_PATH}" \
    -quiet

rm -rf "${DMG_TMP}"

done_msg "DMG created"

# ─── Summary ────────────────────────────────────────────────────────────────────

echo ""
echo "═══════════════════════════════════════════════════"
echo "  App:  ${APP_BUNDLE}"
echo "  DMG:  ${DMG_PATH}"
echo ""
echo "  To install: open ${DMG_PATH}"
echo "═══════════════════════════════════════════════════"
