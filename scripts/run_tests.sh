#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_CACHE="/tmp/displaystudio-clang-cache"
OUT_DIR="/tmp/displaystudio-test-output"

mkdir -p "${MODULE_CACHE}" "${OUT_DIR}"

echo "==> Compiling DisplayStudio Verification Runner..."
swiftc \
    -module-cache-path "${MODULE_CACHE}" \
    -target arm64-apple-macosx14.0 \
    -parse-as-library \
    "${ROOT_DIR}"/Sources/DisplayStudio/Models/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Permissions/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Engine/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Capture/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Captions/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Export/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/App/AppState.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Views/*.swift \
    "${ROOT_DIR}"/Sources/DisplayStudio/Views/Timeline/*.swift \
    "${ROOT_DIR}/scripts/verify_engine.swift" \
    -o "/tmp/VerifyDisplayStudio"

echo "==> Running DisplayStudio Engine, UI & Export Tests..."
/tmp/VerifyDisplayStudio "${OUT_DIR}"
