# Display Studio

A native macOS screen recording and editing app built with SwiftUI. The source includes screen, camera, and audio capture; cursor telemetry and automatic zooms; a multitrack timeline; captions; and video/GIF export.

## Requirements

- macOS 14 or later.
- Apple Silicon for the supplied build and verification scripts, which target `arm64-apple-macosx14.0`.
- Xcode with the macOS SDK and Swift 5.9 or later.

## Build and run

From the repository root:

```sh
bash scripts/build_app.sh
open build/DisplayStudio.app
```

The build script creates an app bundle, includes the Metal shader source and permission descriptions, and attempts local ad hoc code signing. The app opens with an interactive demo project.

For development, open `Package.swift` in Xcode. The package has no third-party dependencies. Use the bundled app when exercising permissions that require its `Info.plist`.

## Verification

```sh
swift test
```

The XCTest suite covers spring physics, automatic zoom generation, timeline mapping, frame rendering, and project persistence.

For the additional macOS engine, UI snapshot, and export checks:

```sh
bash scripts/run_tests.sh
```

This runner uses AppKit and graphics APIs and writes preview images and sample MP4/GIF exports to `/tmp/displaystudio-test-output`.

## Recording permissions

Enable Screen Recording and Accessibility access when prompted. Camera, Microphone, and Speech Recognition permissions are needed for their respective features. These permissions can be managed in macOS System Settings.

## Project layout

- `Sources/DisplayStudio/`: app, capture, editing models, rendering engine, views, captions, and export code.
- `Tests/DisplayStudioTests/`: XCTest coverage.
- `scripts/`: app packaging and verification tools.
- `PROMPT.md`: original product brief retained for reference.

Build output, local credentials, and saved `.displaystudio` project bundles are excluded from version control.

Cloud sharing requires a user-configured upload endpoint. The included fallback share URL is a placeholder, not a hosted sharing service.
