#!/usr/bin/env bash
set -euo pipefail

APP_NAME="AICP"
BUNDLE_ID="com.aicp.app"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIG="${CONFIG:-release}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_ROOT}/.build"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

echo "==> Building ${APP_NAME} v${VERSION} (${CONFIG})..."

# Build the executable
swift build -c "$CONFIG" --package-path "$PROJECT_ROOT"

# Find the built executable
EXEC_PATH="${BUILD_DIR}/${CONFIG}/${APP_NAME}"
if [ ! -f "$EXEC_PATH" ]; then
    echo "Error: executable not found at ${EXEC_PATH}"
    exit 1
fi

echo "==> Creating app bundle..."

# Clean previous bundle
rm -rf "$APP_BUNDLE"

# Create bundle structure
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "$EXEC_PATH" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Embed frameworks that the executable links via @rpath
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
for fw in RiveRuntime Sparkle; do
    FW_SRC="${BUILD_DIR}/${CONFIG}/${fw}.framework"
    if [ -d "$FW_SRC" ]; then
        cp -R "$FW_SRC" "${APP_BUNDLE}/Contents/Frameworks/"
        echo "    Embedded ${fw}.framework"
    fi
done

# Update rpath so the executable finds embedded frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

# Copy SPM-bundled resources (the _Resources bundle that SPM creates)
RESOURCE_BUNDLE="${BUILD_DIR}/${CONFIG}/${APP_NAME}_AICP.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    cp -R "$RESOURCE_BUNDLE" "${APP_BUNDLE}/Contents/Resources/"
    echo "    Copied SPM resource bundle"
fi

# Generate Info.plist
cat > "${APP_BUNDLE}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2025 AICP. MIT License.</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Generate app icon from AppIcon PNG if sips is available
ICON_SOURCE="${PROJECT_ROOT}/Sources/AICP/Resources/AppIcon.png"
if [ -f "$ICON_SOURCE" ] && command -v sips &>/dev/null && command -v iconutil &>/dev/null; then
    echo "==> Generating app icon..."
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"
    for size in 16 32 64 128 256 512; do
        sips -z $size $size "$ICON_SOURCE" --out "${ICONSET_DIR}/icon_${size}x${size}.png" &>/dev/null
        double=$((size * 2))
        sips -z $double $double "$ICON_SOURCE" --out "${ICONSET_DIR}/icon_${size}x${size}@2x.png" &>/dev/null
    done
    iconutil -c icns "$ICONSET_DIR" -o "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    rm -rf "$(dirname "$ICONSET_DIR")"
fi

# Copy entitlements if they exist (used for codesigning)
ENTITLEMENTS="${PROJECT_ROOT}/AICP.entitlements"
if [ -f "$ENTITLEMENTS" ]; then
    cp "$ENTITLEMENTS" "${DIST_DIR}/"
fi

# Codesign the app bundle
# Without signing, macOS won't register the app for notifications, keychain, etc.
if [ "${CODESIGN_IDENTITY:-}" != "" ]; then
    echo "==> Code signing with identity: ${CODESIGN_IDENTITY}"
    codesign --force --deep --options runtime \
        --entitlements "${ENTITLEMENTS}" \
        --sign "$CODESIGN_IDENTITY" \
        "$APP_BUNDLE"
    echo "    Signed with identity"
else
    echo "==> Ad-hoc code signing..."
    codesign --force --deep --sign - \
        --entitlements "${ENTITLEMENTS}" \
        "$APP_BUNDLE"
    echo "    Ad-hoc signed (notifications, keychain will work locally)"
fi

echo "==> App bundle created at: ${APP_BUNDLE}"
echo ""
echo "To run:  open ${APP_BUNDLE}"
echo ""

# Optional: create DMG with drag-to-Applications installer
if [ "${CREATE_DMG:-0}" = "1" ]; then
    echo "==> Creating DMG installer..."
    create-dmg --overwrite "$APP_BUNDLE" "$DIST_DIR" --no-code-sign
    echo "    DMG installer created in: ${DIST_DIR}"
fi

# Optional: create ZIP
if [ "${CREATE_ZIP:-0}" = "1" ]; then
    ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"
    echo "==> Creating ZIP..."
    (cd "$DIST_DIR" && zip -r -q "${APP_NAME}-${VERSION}.zip" "${APP_NAME}.app")
    echo "    ZIP created at: ${ZIP_PATH}"
fi

echo "==> Done!"
