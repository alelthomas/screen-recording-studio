# Master Prompt: Build "Display Studio" — Native macOS Screen Recording & Motion-Design Studio (Screen Studio Clone)

## Role & Objective
You are a Staff macOS Systems & Graphics Engineer. Build **Display Studio**, a native macOS screen recording and post-production studio inspired by [Screen Studio](https://screen.studio/). The application captures raw screen video alongside high-frequency cursor, click, keystroke, webcam, and multi-track audio telemetry, and immediately opens a non-destructive editor that automatically applies cinematic spring-physics zooms, cursor smoothing, directional motion blur, custom backgrounds, webcam picture-in-picture (PiP), auto-captions, and timeline speed ramps.

---

## 1. Target Platform & Technical Stack
- **OS Target**: macOS 14.0+ (Sonoma / Sequoia)
- **Language & Concurrency**: Swift 6 (strict concurrency, `@MainActor` UI orchestration, dedicated serial/concurrent dispatch queues and actors for capture and rendering)
- **UI Framework**: SwiftUI for studio chrome, inspectors, and HUD; `AppKit` (`NSPanel`, `NSWindow`, `NSViewRepresentable`) for floating recording HUDs, region-selection overlay windows, and high-frequency timeline scrubbing
- **Screen & System Audio Capture**: `ScreenCaptureKit` (`SCStream`, `SCContentFilter`, `SCStreamConfiguration`)
- **Webcam & Microphone Capture**: `AVFoundation` (`AVCaptureSession`, `AVCaptureVideoDataOutput`, `AVCaptureAudioDataOutput`, `AVAssetWriter`)
- **Input Telemetry**: `CoreGraphics` `CGEventTap` + `NSEvent` global/local monitors + `AXUIElement` Accessibility APIs
- **Real-Time Preview & Offline Export Compositor**: `Metal` (`MTKView`, custom `.metal` fragment/vertex shaders) + `CoreImage` + `AVVideoComposition` / custom `AVVideoCompositing`
- **Speech-to-Text (Auto-Captions)**: Apple `Speech` framework (`SFSpeechRecognizer`, on-device recognition with word-level timestamps)
- **Export Formats**:
  - `MP4` / `MOV` (`H.264` and `HEVC` via hardware-accelerated `VideoToolbox` / `AVAssetWriter`, up to 4K @ 60fps)
  - `WebM` (`VP9`) and high-quality palette-optimized `GIF` (via embedded `FFmpeg` / `gifski` helper pipeline or native `ImageIO` frame quantization + dithering)
  - Cloud Share uploader (multipart/presigned upload with progress bar and automatic copy of shareable URL to `NSPasteboard`)

---

## 2. Core Architectural Principle: Non-Destructive Metadata Capture
**CRITICAL REQUIREMENT**: Never bake the cursor, zoom, click ripples, keystrokes, or webcam into the primary screen recording during capture.
Instead, every recording session writes to a self-contained `.displaystudio` package directory containing:
1. `screen_raw.mov`: Full-resolution screen/window/region video recorded via `SCStream` with **`showsCursor = false`** so the native OS cursor is hidden in the recorded video buffer while remaining visible to the user during recording.
2. `webcam_raw.mov`: Separate time-synced video stream from the selected camera device.
3. `system_audio.caf` & `mic_audio.caf`: Separate time-synced multi-track audio files.
4. `telemetry.json` (or binary plist): Time-indexed events synchronized to a shared `CMClock` (`CMClockGetHostTimeClock()`):
   - **Cursor samples** at 120 Hz: `{ timestamp: Double, normalizedPos: CGPoint, cursorType: CursorStyle }`
   - **Mouse button events**: `{ timestamp: Double, button: .left | .right | .middle, phase: .down | .up | .drag, position: CGPoint }`
   - **Scroll wheel events**: `{ timestamp: Double, deltaX: Double, deltaY: Double }`
   - **Keyboard shortcut / typing events**: `{ timestamp: Double, characters: String, keyCode: UInt16, modifiers: [ModifierKey], isShortcut: Bool }`
5. `project.json`: Non-destructive editing model (canvas aspect ratio, background style, padding, corner radius, shadow, cursor scale, spring physics parameters, auto/manual zoom segments, trim/split cuts, speed ramp segments, audio track gains, caption segments).

---

## 3. Feature Specifications

### 3.1 Permissions & Onboarding Flow
Build a polished onboarding window that checks, requests, and displays live status indicators for:
1. **Screen Recording Permission** (`CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()`)
2. **Accessibility Permission** (`AXIsProcessTrustedWithOptions`) — required for `CGEventTap` click/keystroke capture and cursor type inspection
3. **Camera & Microphone Permissions** (`AVCaptureDevice.requestAccess(for:)`)
4. **Speech Recognition Permission** (`SFSpeechRecognizer.requestAuthorization`)

### 3.2 Recording Launcher HUD & Capture Modes
- **Floating Control Bar (`NSPanel`)**: Translucent vibrancy pill (`NSVisualEffectView`) floating above all spaces (`level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`), excluded from `SCContentFilter` so the recorder HUD never appears in the recording.
- **3 Capture Target Modes**:
  1. **Full Display**: Select from any connected `SCDisplay` with live thumbnail preview.
  2. **Specific Application Window**: Interactive window picker highlighting hovered `SCWindow` instances; captures the target window cleanly independent of overlapping windows.
  3. **Custom Screen Region**: Interactive drag-to-select overlay with customizable dimension inputs, aspect-ratio lock presets (16:9, 9:16, 1:1, 4:3), and crosshair magnifier.
- **Input Selectors in HUD**:
  - Webcam picker (Off, or select connected camera with live circular/rounded-rect preview bubble)
  - Microphone picker (Off, or select audio input with live level meter)
  - System Audio toggle (On/Off)
  - Countdown timer option (None, 3s, 5s)
- **Menu Bar Recording Controls**: `NSStatusItem` showing recording duration, Pause/Resume, Restart, Cancel, and Stop buttons, plus global hotkey (`Cmd + Shift + 2`).

### 3.3 Cursor System & Spring-Physics Smoothing
- **System Cursor Hiding & Vector Replacement**:
  - Capture raw frames with `SCStreamConfiguration.showsCursor = false`.
  - Detect actual macOS cursor state changes (`arrow`, `iBeam`, `pointingHand`, `crosshair`, `closedHand`, `openHand`, `resizeLeftRight`, `resizeUpDown`) and render crisp, resolution-independent vector cursors in the Metal compositor at any zoom scale (1x to 4x) without pixelation.
- **Spring-Physics Cursor Trajectory Smoothing**:
  - Replace raw, jittery mouse coordinates with a critically/under-damped second-order spring solver:
    ```
    a(t) = -k * (x(t) - x_target(t)) - c * v(t)
    ```
  - Expose user presets (**Instant**, **Natural**, **Smooth**, **Cinematic**) plus fine-grained sliders for **Stiffness (`k`)**, **Damping (`c`)**, and **Mass (`m`)**.
  - Optionally auto-hide idle cursor after `N` seconds of inactivity with a smooth opacity fade.
- **Click Effects**:
  - On `.down` / `.up` mouse events, animate a subtle cursor scale bounce (e.g., shrink to `0.85x` on press, spring back to `1.0x` on release) plus an optional expanding radial ripple ring with customizable color, opacity, and duration.

### 3.4 Automatic & Manual Zoom Engine
- **Auto-Zoom Generator**:
  - Analyze `telemetry.json` immediately after recording stops to automatically generate `ZoomSegment` blocks on the Zoom track:
    - Cluster clicks occurring within a configurable time window (e.g., `2.5s`) into a single zoom hold.
    - Detect typing bursts (keyboard events while focused) and smoothly pan/zoom to the active cursor/caret area.
    - Automatically pan the camera viewport smoothly when the smoothed cursor approaches the edges of the zoomed viewport (dead-zone / follow-cam logic).
- **Manual Zoom Keyframes & Inspector**:
  - Users can click anywhere on the **Zoom Track** in the timeline to add, drag, trim, delete, or merge `ZoomSegment` blocks.
  - Selecting a `ZoomSegment` opens the **Zoom Inspector**:
    - **Mode**: `Follow Cursor` (dynamically tracks smoothed cursor position) or `Fixed Point` (interactive target reticle on the preview canvas to pin the zoom center `(x, y)`).
    - **Zoom Depth**: `1.25x` to `4.0x` slider.
    - **Transition Curve**: Spring physics presets (`Mellow`, `Quick`, `Snappy`, `Bouncy`) controlling zoom-in and zoom-out easing.
- **Directional & Radial Motion Blur**:
  - Compute instantaneous screen-space velocity `(du, dv)` of the camera pan/zoom and cursor movement between frames.
  - In the Metal fragment shader, apply velocity-based directional multi-sample motion blur (e.g., 16-tap directional kernel scaled by shutter angle `0°–360°`) during rapid camera pans, zooms, and fast cursor sweeps.

### 3.5 Canvas, Backgrounds, Frame & Aspect Ratio Styling
- **Aspect Ratio Presets**:
  - `Auto (Native Source)`, `16:9 (Wide)`, `9:16 (Vertical / Reels / Shorts)`, `1:1 (Square)`, `4:3 (Classic)`, `16:10 (macOS)`.
  - Automatically letterbox/pillarbox and center the recorded window/screen inside the target aspect ratio canvas.
- **Background Studio**:
  - **macOS Wallpaper Library**: Built-in curated collection of high-res dynamic gradients and macOS wallpapers.
  - **Gradients**: Multi-stop linear, radial, and mesh gradients with interactive angle and color pickers.
  - **Solid Colors**: Standard color picker + eyedropper.
  - **Custom Image**: Load any user PNG/JPG/HEIC wallpaper with adjustable **Gaussian Blur** slider and brightness/vignette controls.
- **Screen Frame Styling**:
  - **Padding / Inset**: Slider (`0%` to `35%` of canvas size) smoothly scaling the screen recording inside the background.
  - **Corner Radius**: Continuous squircle / rounded corners (`0px` to `64px`) clipped in the Metal shader.
  - **Drop Shadow**: Adjustable shadow opacity, blur radius, Y-offset, and spread around the screen recording card.
  - **Inset Border**: Optional subtle `1px–2px` inner glass highlight border.

### 3.6 Overlays: Webcam PiP, Keystroke Visualizer & Auto-Captions
- **Webcam Picture-in-Picture (PiP)**:
  - Render `webcam_raw.mov` as a floating layer anchored to any corner or freely positioned on the canvas.
  - **Shapes**: Circle, Squircle, Rounded Rectangle (16:9 or 4:3), or Vertical Pill.
  - **Styling**: Resizable scale, custom border width/color, drop shadow, horizontal mirror toggle, and automatic smooth ducking/shrinking (or corner dodge) when a zoom focuses underneath the webcam bubble.
- **Keystroke & Shortcut Visualizer Overlay**:
  - Render a sleek macOS-style floating keycap badge on the canvas (e.g., `⌘ Cmd + ⇧ Shift + P`) when shortcuts or keystrokes occur.
  - Controls: Toggle "Shortcuts Only" vs "All Keystrokes", position (Bottom Center, Top Center, Custom), pill theme (Dark Glass / Light Glass), font size, and fade-out duration.
- **Auto-Captions / Transcript Generation**:
  - Run Apple `SFSpeechRecognizer` on the microphone (or system) audio track to generate word-level timed `CaptionSegment` items on a dedicated **Captions Track**.
  - Interactive transcript editor in the sidebar to fix words, adjust timing, and style captions (font, size, background pill, active-word karaoke highlight, position).

### 3.7 Multi-Track Timeline Editor
Build a responsive, 60fps zoomable timeline at the bottom of the studio window featuring:
1. **Video & Clip Track**:
   - **Trim Handles**: Drag start/end edges of clips.
   - **Split Tool (`S` or `Cmd + B`)**: Slice the recording at the playhead and delete unwanted segments (ripple delete automatically shifts subsequent zoom/speed/caption segments).
   - **Speed Ramps Track / Segments**: Select any time range or split clip to apply playback speed multipliers (`0.5x`, `1x`, `1.5x`, `2x`, `4x`, `8x`) with smooth ease-in/ease-out speed ramping and pitch-corrected or muted audio during fast-forward segments.
2. **Zoom Track**: Color-coded purple blocks showing zoom-in ramp, hold plateau, and zoom-out ramp with draggable handles.
3. **Audio Waveform Tracks**:
   - Separate visual waveforms for **Microphone Audio** and **System Audio**.
   - Independent volume gain sliders (`0%–200%`), mute toggles, noise reduction / voice isolation toggle, and auto-ducking (automatically lowers system audio by `-12dB` when microphone speech is detected).
4. **Captions Track**: Editable subtitle blocks aligned with the audio waveform.

### 3.8 Export Pipeline & Shareable Cloud Link
- **Export Sheet UI**:
  - **Format**: `MP4 (H.264 / HEVC)`, `WebM`, `GIF`
  - **Resolution**: `720p`, `1080p`, `1440p`, `4K (3840×2160)`
  - **Frame Rate**: `24 fps`, `30 fps`, `60 fps`
  - **Quality / Bitrate Preset**: `Web Optimized`, `High`, `Studio Master (ProRes 422 / High-Bitrate HEVC)`
  - Real-time export progress bar with estimated time remaining, rendered frame preview, and FPS counter.
- **Shareable Cloud Link**:
  - One-click **"Copy Shareable Link"** button that exports an optimized 1080p/60fps MP4, uploads it to a configurable S3-compatible / Cloudflare R2 / custom endpoint via presigned URL, copies the shareable viewer link to `NSPasteboard`, and triggers a macOS notification.

---

## 4. UI / UX Layout Specification
Design a dark-mode-first, native macOS pro-studio interface (`NSWindow` with unified toolbar):
- **Top Toolbar**: Project title, Undo/Redo, Aspect Ratio selector dropdown, Canvas Zoom (`Fit`, `50%`, `100%`), **"New Recording"** button, **"Share Link"** button, and primary **"Export"** CTA.
- **Center Stage**: Metal-backed `MTKView` preview canvas with interactive overlays (draggable webcam PiP, draggable fixed-zoom target reticle, playback transport bar with timecode `00:00.00`).
- **Right Inspector Sidebar (Tabbed)**:
  - **Background & Frame Tab**: Wallpaper gallery, gradient/color/image tabs, padding, rounded corners, shadow, inset border.
  - **Cursor & Zoom Tab**: Cursor size, cursor style, spring smoothness preset & sliders, click ripple toggle, motion blur intensity, selected ZoomSegment controls.
  - **Webcam & Audio Tab**: Webcam shape/size/shadow/mirror, Mic & System volume sliders, voice isolation, auto-ducking.
  - **Captions & Keys Tab**: "Generate Auto-Captions" button, transcript list editor, caption styling, keystroke visualizer settings.
- **Bottom Dock**: Multi-track timeline with playhead scrubber, Split (`Cmd+B`), Add Zoom (`Z`), Add Speed Ramp (`R`), timeline zoom slider, and track headers.

---

## 5. Required Project Structure & Implementation Phases
Organize the Xcode / Swift Package Manager project cleanly into modular targets or groups:

```text
DisplayStudio/
├── App/
│   ├── DisplayStudioApp.swift
│   └── AppState.swift
├── Permissions/
│   └── PermissionManager.swift
├── Capture/
│   ├── CaptureCoordinator.swift        // Orchestrates SCStream, AVCaptureSession, EventTap
│   ├── ScreenRecorder.swift            // ScreenCaptureKit raw capture (showsCursor = false)
│   ├── CameraAudioRecorder.swift       // Webcam + Mic + System audio writers
│   ├── InputTelemetryMonitor.swift     // CGEventTap 120Hz cursor, click, scroll, keystrokes
│   └── RecordingHUDPanel.swift         // Floating NSPanel & region selector overlay
├── Models/
│   ├── ProjectBundle.swift             // .displaystudio package read/write
│   ├── TelemetryModels.swift           // CursorSample, ClickEvent, KeystrokeEvent
│   └── TimelineModels.swift            // ZoomSegment, SpeedSegment, TrimClip, CaptionSegment
├── Engine/
│   ├── SpringPhysicsSolver.swift       // 2nd-order ODE cursor & camera smoothing
│   ├── AutoZoomGenerator.swift         // Click-clustering & typing-burst zoom heuristics
│   ├── MetalCompositor.swift           // Real-time MTKView & offline AVAssetWriter renderer
│   ├── Shaders.metal                   // Background, squircle mask, drop shadow, motion blur
│   └── VectorCursorRenderer.swift      // Crisp scalable vector macOS cursors + click ripples
├── Captions/
│   └── SpeechCaptionService.swift      // On-device SFSpeechRecognizer word-level timestamps
├── Export/
│   ├── VideoExportPipeline.swift       // MP4/HEVC, WebM, and GIF export engines
│   └── CloudShareService.swift         // Presigned upload & clipboard link sharing
└── Views/
    ├── StudioMainWindow.swift
    ├── PreviewCanvasView.swift
    ├── InspectorSidebarView.swift
    ├── Timeline/
    │   ├── MultiTrackTimelineView.swift
    │   ├── WaveformTrackView.swift
    │   └── ZoomTrackView.swift
    └── ExportSheetView.swift
```

### Execution Instructions
1. **No Placeholders or Stubs**: Implement complete, compilable Swift 6 code for all modules, including the `.metal` shaders, spring-physics integrator, `ScreenCaptureKit` stream delegate, `CGEventTap` telemetry recorder, and `AVAssetWriter` export pipeline.
2. **Build & Verify Iteratively**:
   - Step 1: Set up the Swift Package / Xcode project (`Package.swift` / `.xcodeproj`), `Info.plist` privacy usage descriptions (`NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`), and entitlements.
   - Step 2: Implement the `Capture` layer and verify `.displaystudio` bundle recording with synchronized `CMTime` clocks.
   - Step 3: Implement `SpringPhysicsSolver`, `AutoZoomGenerator`, and `Shaders.metal` for real-time 60fps preview rendering.
   - Step 4: Implement the SwiftUI Studio interface, Inspector tabs, and Multi-Track Timeline (Zoom, Trim/Split, Speed Ramps, Audio Waveforms, Captions).
   - Step 5: Implement the `VideoExportPipeline` (MP4/HEVC, WebM, GIF) and `CloudShareService`, and verify compilation with `swift build` / `xcodebuild`.
