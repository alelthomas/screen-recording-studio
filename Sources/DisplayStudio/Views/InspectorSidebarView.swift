import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers

public struct InspectorSidebarView: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Inspector Tab Selector Bar
            HStack(spacing: 4) {
                ForEach(InspectorTab.allCases) { tab in
                    Button {
                        appState.selectedInspectorTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 13, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(size: 10, weight: .medium))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            appState.selectedInspectorTab == tab
                                ? Color.accentColor.opacity(0.24)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .foregroundStyle(appState.selectedInspectorTab == tab ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.black.opacity(0.22))

            Divider()

            // Active Inspector Scroll Content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch appState.selectedInspectorTab {
                    case .background:
                        BackgroundInspectorSection(appState: appState)
                    case .cursorZoom:
                        CursorAndZoomInspectorSection(appState: appState)
                    case .webcamAudio:
                        WebcamAndAudioInspectorSection(appState: appState)
                    case .captionsKeys:
                        CaptionsAndKeysInspectorSection(appState: appState)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 345)
        .background(Color(nsColor: NSColor(srgbRed: 0.10, green: 0.11, blue: 0.15, alpha: 1.0)))
    }
}

// MARK: - 1. Background & Frame Styling Inspector

private struct BackgroundInspectorSection: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSectionHeader(title: "Background Mode", icon: "sparkles.rectangle.stack")

            Picker("Mode", selection: $appState.project.background.mode) {
                ForEach(BackgroundMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch appState.project.background.mode {
            case .wallpaper:
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(WallpaperPreset.allCases) { preset in
                        let isSelected = appState.project.background.wallpaperPreset == preset
                        Button {
                            appState.recordUndoSnapshot()
                            appState.project.background.wallpaperPreset = preset
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                LinearGradient(
                                    colors: preset.colors.map(\.swiftUIColor),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                .frame(height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .stroke(isSelected ? Color.white : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                                )
                                Text(preset.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundStyle(isSelected ? .white : .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .gradient, .mesh:
                VStack(alignment: .leading, spacing: 10) {
                    ColorRowPicker(label: "Primary Color", codableColor: $appState.project.background.gradientStart)
                    ColorRowPicker(label: "Secondary Color", codableColor: $appState.project.background.gradientEnd)
                    if appState.project.background.mode == .mesh {
                        ColorRowPicker(label: "Mesh Orb Accent", codableColor: $appState.project.background.gradientAccent)
                    } else {
                        LabeledSlider(
                            title: "Gradient Angle",
                            value: $appState.project.background.gradientAngleDegrees,
                            range: 0...360,
                            unit: "°"
                        )
                    }
                }

            case .solid:
                ColorRowPicker(label: "Canvas Color", codableColor: $appState.project.background.solidColor)

            case .customImage:
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(appState.project.background.customImagePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No image selected")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("Choose Image…") {
                            chooseCustomBackdropImage()
                        }
                        .controlSize(.small)
                    }
                    LabeledSlider(
                        title: "Backdrop Blur",
                        value: $appState.project.background.backdropBlurRadius,
                        range: 0...60,
                        unit: "px"
                    )
                }
            }

            LabeledSlider(
                title: "Vignette",
                value: $appState.project.background.vignetteIntensity,
                range: 0...0.65,
                format: "%.0f%%",
                multiplier: 100
            )
            LabeledSlider(
                title: "Brightness Offset",
                value: $appState.project.background.brightness,
                range: -0.35...0.35,
                format: "%+.0f%%",
                multiplier: 100
            )

            Divider()

            InspectorSectionHeader(title: "Screen Frame & Shadow", icon: "macwindow")

            LabeledSlider(
                title: "Padding / Inset",
                value: $appState.project.frameStyling.paddingRatio,
                range: 0.0...0.30,
                format: "%.0f%%",
                multiplier: 100
            )
            LabeledSlider(
                title: "Corner Radius",
                value: $appState.project.frameStyling.cornerRadius,
                range: 0...56,
                unit: "px"
            )
            LabeledSlider(
                title: "Shadow Intensity",
                value: $appState.project.frameStyling.shadowOpacity,
                range: 0...1.0,
                format: "%.0f%%",
                multiplier: 100
            )
            LabeledSlider(
                title: "Shadow Blur",
                value: $appState.project.frameStyling.shadowRadius,
                range: 0...80,
                unit: "px"
            )
            LabeledSlider(
                title: "Glass Inset Border",
                value: $appState.project.frameStyling.insetBorderOpacity,
                range: 0...0.85,
                format: "%.0f%%",
                multiplier: 100
            )
        }
    }

    private func chooseCustomBackdropImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appState.recordUndoSnapshot()
            appState.project.background.customImagePath = url.path
        }
    }
}

// MARK: - 2. Cursor, Spring Physics & Zoom Keyframe Inspector

private struct CursorAndZoomInspectorSection: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSectionHeader(title: "Cursor & Spring Physics", icon: "cursorarrow.motionlines")

            Toggle("Render Custom Vector Cursor", isOn: $appState.project.cursorSettings.showCursor)
                .font(.system(size: 12, weight: .medium))

            LabeledSlider(
                title: "Cursor Size",
                value: $appState.project.cursorSettings.scale,
                range: 0.75...3.5,
                format: "%.2fx"
            )

            Picker("Smoothness Preset", selection: $appState.project.cursorSettings.springPreset) {
                ForEach(SpringPreset.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .font(.system(size: 12))
            .onChange(of: appState.project.cursorSettings.springPreset) { _, newPreset in
                if newPreset != .custom {
                    let params = newPreset.parameters
                    appState.project.cursorSettings.stiffness = params.stiffness
                    appState.project.cursorSettings.damping = params.damping
                    appState.project.cursorSettings.mass = params.mass
                }
            }

            if appState.project.cursorSettings.springPreset == .custom {
                LabeledSlider(
                    title: "Spring Stiffness (k)",
                    value: $appState.project.cursorSettings.stiffness,
                    range: 40...800,
                    format: "%.0f"
                )
                LabeledSlider(
                    title: "Spring Damping (c)",
                    value: $appState.project.cursorSettings.damping,
                    range: 8...70,
                    format: "%.0f"
                )
            }

            Toggle("Auto-Hide Idle Cursor", isOn: $appState.project.cursorSettings.autoHideIdle)
                .font(.system(size: 12))

            Toggle("Click Ripple Ring & Bounce", isOn: $appState.project.cursorSettings.showClickRipple)
                .font(.system(size: 12))

            if appState.project.cursorSettings.showClickRipple {
                ColorRowPicker(label: "Click Ripple Color", codableColor: $appState.project.cursorSettings.rippleColor)
                LabeledSlider(
                    title: "Click Bounce Scale",
                    value: $appState.project.cursorSettings.clickBounceScale,
                    range: 0.65...1.0,
                    format: "%.2fx"
                )
            }

            Divider()

            InspectorSectionHeader(title: "Directional Motion Blur", icon: "wind")

            LabeledSlider(
                title: "Blur Intensity",
                value: $appState.project.cursorSettings.motionBlurIntensity,
                range: 0.0...1.0,
                format: "%.0f%%",
                multiplier: 100
            )
            LabeledSlider(
                title: "Shutter Angle",
                value: $appState.project.cursorSettings.shutterAngleDegrees,
                range: 0...360,
                unit: "°"
            )

            Divider()

            // Selected Zoom Segment Inspector
            HStack {
                InspectorSectionHeader(title: "Zoom Keyframes", icon: "plus.magnifyingglass")
                Spacer()
                Button("+ Add at Playhead") {
                    appState.addZoomSegmentAtPlayhead()
                }
                .controlSize(.small)
            }

            if let selectedID = appState.selectedZoomSegmentID,
               let idx = appState.project.zoomSegments.firstIndex(where: { $0.id == selectedID }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(String(format: "Segment %.1fs – %.1fs", appState.project.zoomSegments[idx].startTime, appState.project.zoomSegments[idx].endTime))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.purple)
                        Spacer()
                        Button(role: .destructive) {
                            appState.deleteSelectedZoomSegment()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }

                    LabeledSlider(
                        title: "Zoom Depth",
                        value: $appState.project.zoomSegments[idx].zoomDepth,
                        range: 1.2...4.0,
                        format: "%.2fx"
                    )

                    Picker("Zoom Tracking", selection: Binding(
                        get: { appState.project.zoomSegments[idx].mode.isFollowCursor },
                        set: { follow in
                            appState.project.zoomSegments[idx].mode = follow
                                ? .followCursor
                                : .fixedPoint(appState.currentFrameState.smoothedCursorPos)
                        }
                    )) {
                        Text("Follow Cursor").tag(true)
                        Text("Fixed Point").tag(false)
                    }
                    .pickerStyle(.segmented)

                    Picker("Spring Curve", selection: $appState.project.zoomSegments[idx].transitionPreset) {
                        ForEach(ZoomTransitionPreset.allCases) { curve in
                            Text(curve.rawValue).tag(curve)
                        }
                    }
                    .font(.system(size: 12))
                }
                .padding(10)
                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Text("Select a purple Zoom block on the timeline or click '+ Add at Playhead'.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                appState.regenerateAutoZooms()
            } label: {
                Label("Re-Generate Auto-Zooms from Clicks", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
    }
}

// MARK: - 3. Webcam PiP & Multi-Track Audio Inspector

private struct WebcamAndAudioInspectorSection: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSectionHeader(title: "Webcam Picture-in-Picture", icon: "person.crop.square")

            Toggle("Enable Webcam Overlay", isOn: $appState.project.webcamSettings.isEnabled)
                .font(.system(size: 12, weight: .medium))

            if appState.project.webcamSettings.isEnabled {
                Picker("Shape", selection: $appState.project.webcamSettings.shape) {
                    ForEach(WebcamShape.allCases) { shape in
                        Text(shape.rawValue).tag(shape)
                    }
                }
                .font(.system(size: 12))

                Picker("Anchor Corner", selection: $appState.project.webcamSettings.corner) {
                    ForEach(WebcamCorner.allCases) { corner in
                        Text(corner.rawValue).tag(corner)
                    }
                }
                .font(.system(size: 12))

                LabeledSlider(
                    title: "Webcam Size",
                    value: $appState.project.webcamSettings.scale,
                    range: 0.12...0.40,
                    format: "%.0f%%",
                    multiplier: 100
                )

                LabeledSlider(
                    title: "Border Width",
                    value: $appState.project.webcamSettings.borderWidth,
                    range: 0...10,
                    unit: "px"
                )

                ColorRowPicker(label: "Border Color", codableColor: $appState.project.webcamSettings.borderColor)

                Toggle("Mirror Webcam Horizontally", isOn: $appState.project.webcamSettings.isMirrored)
                    .font(.system(size: 12))

                Toggle("Auto-Duck Size When Zooming Corner", isOn: $appState.project.webcamSettings.autoDuckOnZoom)
                    .font(.system(size: 12))
            }

            Divider()

            InspectorSectionHeader(title: "Multi-Track Audio Mixer", icon: "waveform.circle")

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Toggle("Microphone Track", isOn: Binding(
                        get: { !appState.project.audioSettings.isMicMuted },
                        set: { appState.project.audioSettings.isMicMuted = !$0 }
                    ))
                    .font(.system(size: 12, weight: .semibold))
                }
                LabeledSlider(
                    title: "Mic Gain",
                    value: $appState.project.audioSettings.micVolume,
                    range: 0.0...2.0,
                    format: "%.0f%%",
                    multiplier: 100
                )
                .disabled(appState.project.audioSettings.isMicMuted)

                HStack {
                    Toggle("System Audio Track", isOn: Binding(
                        get: { !appState.project.audioSettings.isSystemMuted },
                        set: { appState.project.audioSettings.isSystemMuted = !$0 }
                    ))
                    .font(.system(size: 12, weight: .semibold))
                }
                LabeledSlider(
                    title: "System Volume",
                    value: $appState.project.audioSettings.systemVolume,
                    range: 0.0...2.0,
                    format: "%.0f%%",
                    multiplier: 100
                )
                .disabled(appState.project.audioSettings.isSystemMuted)

                Toggle("Voice Isolation (Noise Reduction)", isOn: $appState.project.audioSettings.voiceIsolation)
                    .font(.system(size: 12))

                Toggle("Auto-Duck System Audio During Speech (-12dB)", isOn: $appState.project.audioSettings.autoDuckSystemAudio)
                    .font(.system(size: 12))
            }
        }
    }
}

// MARK: - 4. Auto-Captions & Keystroke Visualizer Inspector

private struct CaptionsAndKeysInspectorSection: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InspectorSectionHeader(title: "Auto-Captions (Apple Speech)", icon: "captions.bubble")

            HStack {
                Toggle("Show Captions on Canvas", isOn: $appState.project.captionStyle.isEnabled)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Button {
                    appState.generateAutoCaptions()
                } label: {
                    Label(
                        appState.captionService.isTranscribing ? "Transcribing…" : "Auto-Transcribe",
                        systemImage: "waveform.badge.magnifyingglass"
                    )
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(appState.captionService.isTranscribing)
            }

            if !appState.captionService.statusMessage.isEmpty {
                Text(appState.captionService.statusMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            LabeledSlider(
                title: "Caption Font Size",
                value: $appState.project.captionStyle.fontSize,
                range: 14...42,
                unit: "pt"
            )
            ColorRowPicker(label: "Caption Text Color", codableColor: $appState.project.captionStyle.activeWordHighlightColor)

            // Editable Transcript List
            VStack(alignment: .leading, spacing: 6) {
                Text("Transcript Segments (\(appState.project.captionSegments.count))")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach($appState.project.captionSegments) { $segment in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Button {
                                appState.seek(to: segment.startTime)
                            } label: {
                                Text(String(format: "%.1fs – %.1fs", segment.startTime, segment.endTime))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.cyan)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Button {
                                appState.project.captionSegments.removeAll { $0.id == segment.id }
                            } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        TextField("Caption text", text: $segment.text)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                    }
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Divider()

            InspectorSectionHeader(title: "Keystroke & Shortcut Visualizer", icon: "keyboard")

            Toggle("Display Keystrokes on Screen", isOn: $appState.project.keystrokeSettings.isEnabled)
                .font(.system(size: 12, weight: .medium))

            if appState.project.keystrokeSettings.isEnabled {
                Toggle("Command Shortcuts Only (⌘, ⇧, ⌥, ⌃)", isOn: $appState.project.keystrokeSettings.shortcutsOnly)
                    .font(.system(size: 12))

                Picker("Badge Position", selection: $appState.project.keystrokeSettings.position) {
                    ForEach(OverlayPosition.allCases) { pos in
                        Text(pos.rawValue).tag(pos)
                    }
                }
                .font(.system(size: 12))

                Picker("Pill Theme", selection: $appState.project.keystrokeSettings.theme) {
                    ForEach(KeystrokeTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .font(.system(size: 12))

                LabeledSlider(
                    title: "Badge Size",
                    value: $appState.project.keystrokeSettings.fontSize,
                    range: 12...30,
                    unit: "pt"
                )
            }
        }
    }
}

// MARK: - Reusable Inspector Controls

private struct InspectorSectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 12, weight: .bold))
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""
    var format: String? = nil
    var multiplier: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedValue)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }

    private var formattedValue: String {
        if let format {
            return String(format: format, value * multiplier)
        }
        return "\(Int(round(value * multiplier)))\(unit)"
    }
}

private struct ColorRowPicker: View {
    let label: String
    @Binding var codableColor: CodableColor

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            ColorPicker(
                "",
                selection: Binding(
                    get: { codableColor.swiftUIColor },
                    set: { newSwiftUIColor in
                        let ns = NSColor(newSwiftUIColor)
                        codableColor = CodableColor(nsColor: ns)
                    }
                ),
                supportsOpacity: true
            )
            .labelsHidden()
        }
    }
}
