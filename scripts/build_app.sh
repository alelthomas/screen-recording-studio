#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
APP_BUNDLE="${BUILD_DIR}/DisplayStudio.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MODULE_CACHE="/tmp/displaystudio-clang-cache"

mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${MODULE_CACHE}"

echo "==> Compiling DisplayStudio native macOS binary (arm64-apple-macosx14.0)..."
swiftc \
    -O \
    -module-cache-path "${MODULE_CACHE}" \
    -target arm64-apple-macosx14.0 \
    -parse-as-library \
    "${ROOT_DIR}"/Sources/DisplayStudio/Models/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Permissions/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Engine/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Capture/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Captions/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Export/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/App/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Views/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Views/Timeline/*.swift \
    -o "${MACOS_DIR}/DisplayStudio"

cp "${ROOT_DIR}/Sources/DisplayStudio/Engine/Shaders.metal" "${RESOURCES_DIR}/Shaders.metal"

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>DisplayStudio</string>
    <key>CFBundleIdentifier</key>
    <string>com.antigravity.displaystudio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Display Studio</string>
    <key>CFBundleDisplayName</key>
    <string>Display Studio</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>Display Studio uses your camera to render a customizable Picture-in-Picture presenter overlay.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Display Studio records your microphone on a dedicated audio track for voiceover and auto-captions.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Display Studio uses on-device speech recognition to generate word-level timed captions.</string>
</dict>
</plist>
EOF

codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

echo "==> Successfully built ${APP_BUNDLE}"
