#!/usr/bin/env bash
#
# build-app.sh — Build OpenType.app and (optionally) package it as a DMG.
#
# Usage:
#   ./scripts/build-app.sh              # build .app + .dmg
#   ./scripts/build-app.sh --app-only   # build .app only
#   ./scripts/build-app.sh --help       # show help
#
# Requirements:
#   - macOS with Xcode command-line tools
#   - Swift 6.0+
#

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────────

APP_NAME="OpenType"
BUNDLE_ID="com.opentype.voiceinput"
VERSION="${VERSION:-1.0.0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BUILD_DIR="${PROJECT_DIR}/.build/arm64-apple-macosx/release"
DIST_DIR="${PROJECT_DIR}/dist"
APP_ONLY=false

# ─── Parse arguments ────────────────────────────────────────────────────────────

for arg in "$@"; do
    case "$arg" in
        --app-only)  APP_ONLY=true ;;
        --version=*) VERSION="${arg#*=}" ;;
        --help|-h)
            echo "Usage: $0 [--version=X.Y.Z] [--app-only] [--help]"
            echo ""
            echo "  --version=X.Y.Z  Set version (default: 1.0.0, or \$VERSION env)"
            echo "  --app-only       Build .app bundle only, skip DMG creation"
            echo "  --help           Show this help"
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

# ─── Step 1: Build ──────────────────────────────────────────────────────────────

step "Building ${APP_NAME} (release)…"
cd "${PROJECT_DIR}"
swift build -c release
done_msg "Build succeeded"

# ─── Step 2: Assemble .app bundle ───────────────────────────────────────────────

step "Assembling ${APP_NAME}.app…"

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Binary
cp "${BUILD_DIR}/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/"

# Info.plist (with version injected)
cp "${PROJECT_DIR}/Resources/Info.plist" "${APP_BUNDLE}/Contents/"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "${APP_BUNDLE}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}"           "${APP_BUNDLE}/Contents/Info.plist"

# PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

# SPM resource bundle
if [ -d "${BUILD_DIR}/OpenType_OpenType.bundle" ]; then
    cp -R "${BUILD_DIR}/OpenType_OpenType.bundle" "${APP_BUNDLE}/Contents/Resources/"
fi

done_msg "App bundle assembled"

# ─── Step 3: Generate app icon ──────────────────────────────────────────────────

step "Generating AppIcon.icns…"
swift "${SCRIPT_DIR}/generate-icon.swift" "${APP_BUNDLE}/Contents/Resources"
done_msg "Icon generated"

# ─── Step 4: Code sign (ad-hoc) ────────────────────────────────────────────────

step "Code signing (ad-hoc)…"
codesign --force --deep --sign - "${APP_BUNDLE}"
done_msg "Signed"

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
