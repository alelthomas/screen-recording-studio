import Foundation
import SwiftUI
import AppKit

// MARK: - Export & Cloud Share Modal Sheet

public struct ExportSheetView: View {
    @ObservedObject public var appState: AppState
    @ObservedObject public var pipeline: VideoExportPipeline
    @ObservedObject public var cloudShare: CloudShareService
    public var onDismiss: () -> Void

    public init(
        appState: AppState,
        pipeline: VideoExportPipeline,
        cloudShare: CloudShareService,
        onDismiss: @escaping () -> Void
    ) {
        self.appState = appState
        self.pipeline = pipeline
        self.cloudShare = cloudShare
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.accentColor)
                    Text("Export & Share Studio Video")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(pipeline.isExporting)
            }

            Divider()

            // Export Parameters Form
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Format")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $appState.project.exportSettings.format) {
                        ForEach(ExportFormat.allCases) { fmt in
                            Text(fmt.rawValue).tag(fmt)
                        }
                    }
                    .labelsHidden()
                }

                GridRow {
                    Text("Resolution")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $appState.project.exportSettings.resolution) {
                        ForEach(ExportResolution.allCases) { res in
                            Text(res.rawValue).tag(res)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                GridRow {
                    Text("Frame Rate")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $appState.project.exportSettings.fps) {
                        Text("24 fps").tag(24)
                        Text("30 fps").tag(30)
                        Text("60 fps").tag(60)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                GridRow {
                    Text("Quality Preset")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $appState.project.exportSettings.quality) {
                        ForEach(ExportQuality.allCases) { q in
                            Text(q.rawValue).tag(q)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .disabled(pipeline.isExporting)

            // Output Summary Card
            let targetSize = appState.project.aspectRatio.canvasSize(
                for: appState.project.telemetry.sourceSize,
                baseHeight: appState.project.exportSettings.resolution.baseHeight
            )
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Output Dimensions: \(Int(targetSize.width)) × \(Int(targetSize.height)) (\(appState.project.aspectRatio.rawValue))")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Duration: \(String(format: "%.1fs", appState.project.totalTimelineDuration)) • Spring Physics & Directional Motion Blur Active")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))

            // Progress Indicator
            if pipeline.isExporting || pipeline.progress > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(pipeline.statusText)
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        if pipeline.isExporting {
                            Text(String(format: "%.0f%% • %.1f fps", pipeline.progress * 100, pipeline.renderedFPS))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                    }
                    ProgressView(value: pipeline.progress)
                        .progressViewStyle(.linear)
                }
            }

            if let exportedURL = pipeline.lastExportedURL, !pipeline.isExporting {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Saved to \(exportedURL.lastPathComponent)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([exportedURL])
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            if let shareURL = cloudShare.latestShareURL {
                HStack {
                    Image(systemName: "link.circle.fill")
                        .foregroundStyle(.cyan)
                    Text(shareURL)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button("Copy Again") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(shareURL, forType: .string)
                    }
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.cyan.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            // Footer Buttons
            HStack(spacing: 10) {
                Button {
                    Task {
                        await cloudShare.exportAndCopyShareLink(
                            project: appState.project,
                            bundleURL: appState.bundleURL,
                            exportPipeline: pipeline
                        )
                    }
                } label: {
                    Label(
                        cloudShare.isSharing ? "Uploading Link…" : "Copy Shareable Cloud Link",
                        systemImage: "icloud.and.arrow.up"
                    )
                }
                .disabled(pipeline.isExporting || cloudShare.isSharing)

                Spacer()

                if pipeline.isExporting {
                    Button("Cancel Export", role: .destructive) {
                        pipeline.cancelExport()
                    }
                } else {
                    Button("Close") {
                        onDismiss()
                    }

                    Button {
                        startSavePanelExport()
                    } label: {
                        Label("Export Video…", systemImage: "film.stack")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 530)
    }

    private func startSavePanelExport() {
        let ext = appState.project.exportSettings.format.fileExtension
        let safeTitle = appState.project.title
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
        let defaultName = "\(safeTitle).\(ext)"

        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = defaultName
        savePanel.canCreateDirectories = true

        if savePanel.runModal() == .OK, let destURL = savePanel.url {
            Task {
                _ = try? await pipeline.exportProject(
                    appState.project,
                    bundleURL: appState.bundleURL,
                    destinationURL: destURL
                )
            }
        }
    }
}

// MARK: - Permissions Onboarding Sheet

public struct PermissionsOnboardingSheetView: View {
    @ObservedObject public var permissions: PermissionManager
    public var onDismiss: () -> Void

    public init(permissions: PermissionManager, onDismiss: @escaping () -> Void) {
        self.permissions = permissions
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS System Permissions")
                        .font(.system(size: 15, weight: .bold))
                    Text("Grant permissions for ScreenCaptureKit, 120Hz Cursor Telemetry, Webcam, Mic & Speech.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(spacing: 10) {
                PermissionRow(
                    title: "Screen Recording",
                    subtitle: "Required for ScreenCaptureKit display, window, and custom region capture.",
                    icon: "display",
                    isGranted: permissions.hasScreenRecordingPermission,
                    action: { permissions.requestScreenRecordingPermission() }
                )
                PermissionRow(
                    title: "Accessibility & Input Monitoring",
                    subtitle: "Required for 120Hz cursor coordinates, click clustering, and shortcut badges.",
                    icon: "cursorarrow.click.2",
                    isGranted: permissions.hasAccessibilityPermission,
                    action: { permissions.requestAccessibilityPermission() }
                )
                PermissionRow(
                    title: "Camera (Webcam PiP)",
                    subtitle: "Optional — used for Picture-in-Picture presenter overlay.",
                    icon: "web.camera",
                    isGranted: permissions.hasCameraPermission,
                    action: { permissions.requestCameraPermission() }
                )
                PermissionRow(
                    title: "Microphone",
                    subtitle: "Optional — used for voiceover narration and auto-ducking.",
                    icon: "mic.fill",
                    isGranted: permissions.hasMicrophonePermission,
                    action: { permissions.requestMicrophonePermission() }
                )
                PermissionRow(
                    title: "Speech Recognition (On-Device Auto-Captions)",
                    subtitle: "Optional — generates word-level timed captions automatically.",
                    icon: "captions.bubble",
                    isGranted: permissions.hasSpeechPermission,
                    action: { permissions.requestSpeechPermission() }
                )
            }

            HStack {
                Button("Refresh Status") {
                    permissions.refreshAllStatuses()
                }
                .controlSize(.small)
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            permissions.refreshAllStatuses()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let subtitle: String
    let icon: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isGranted ? .green : .orange)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Grant") {
                    action()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}
