import Foundation
import SwiftUI
import AppKit

// MARK: - Floating Recording Launcher HUD View

public struct RecordingLauncherHUDView: View {
    @ObservedObject public var coordinator: CaptureCoordinator
    @ObservedObject public var permissions: PermissionManager
    public var onDismiss: () -> Void
    public var onOpenRegionSelector: () -> Void

    public init(
        coordinator: CaptureCoordinator,
        permissions: PermissionManager,
        onDismiss: @escaping () -> Void,
        onOpenRegionSelector: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.permissions = permissions
        self.onDismiss = onDismiss
        self.onOpenRegionSelector = onOpenRegionSelector
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(coordinator.isRecording ? Color.red : Color.blue)
                        .frame(width: 10, height: 10)
                    Text(coordinator.isRecording ? "Recording in Progress" : "New Screen Recording")
                        .font(.system(size: 14, weight: .bold))
                }
                Spacer()
                if coordinator.isRecording {
                    Text(formatDuration(coordinator.elapsedSeconds))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.14), in: Capsule())
                }
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if !permissions.hasScreenRecordingPermission {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                    Text("Screen Recording permission is required to capture your display.")
                        .font(.system(size: 12))
                    Spacer()
                    Button("Grant Access") {
                        permissions.requestScreenRecordingPermission()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            }

            // Capture Target Mode Picker
            HStack(spacing: 8) {
                ForEach(CaptureTargetMode.allCases) { mode in
                    Button {
                        coordinator.targetMode = mode
                        if mode == .customRegion {
                            onOpenRegionSelector()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: mode.systemIcon)
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            coordinator.targetMode == mode
                                ? Color.accentColor.opacity(0.26)
                                : Color.white.opacity(0.05),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(coordinator.targetMode == mode ? Color.accentColor : Color.white.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(coordinator.isRecording)
                }
            }

            // Target Source Configuration
            Group {
                switch coordinator.targetMode {
                case .fullDisplay:
                    Picker("Display", selection: $coordinator.selectedDisplayID) {
                        if coordinator.availableDisplays.isEmpty {
                            Text("Main Display (Default)").tag(Optional<CGDirectDisplayID>.none)
                        }
                        ForEach(coordinator.availableDisplays) { disp in
                            Text(disp.displayName).tag(Optional(disp.id))
                        }
                    }
                    .font(.system(size: 12))

                case .window:
                    Picker("Application Window", selection: $coordinator.selectedWindowID) {
                        if coordinator.availableWindows.isEmpty {
                            Text("No external windows detected").tag(Optional<CGWindowID>.none)
                        }
                        ForEach(coordinator.availableWindows) { win in
                            Text("\(win.appName) — \(win.title)").tag(Optional(win.id))
                        }
                    }
                    .font(.system(size: 12))

                case .customRegion:
                    HStack(spacing: 10) {
                        Text("Region: \(Int(coordinator.customRegionRect.width)) × \(Int(coordinator.customRegionRect.height)) at (\(Int(coordinator.customRegionRect.minX)), \(Int(coordinator.customRegionRect.minY)))")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Select Interactive Region…") {
                            onOpenRegionSelector()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .disabled(coordinator.isRecording)

            Divider()

            // Webcam, Microphone & System Audio Pickers
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Label("Webcam", systemImage: "web.camera")
                        .font(.system(size: 12, weight: .medium))
                    Picker("", selection: $coordinator.selectedCameraID) {
                        Text("Off (Or Use Studio Avatar)").tag(Optional<String>.none)
                        ForEach(coordinator.availableCameras) { cam in
                            Text(cam.name).tag(Optional(cam.id))
                        }
                    }
                    .labelsHidden()
                }

                GridRow {
                    Label("Microphone", systemImage: "mic.fill")
                        .font(.system(size: 12, weight: .medium))
                    HStack(spacing: 8) {
                        Picker("", selection: $coordinator.selectedMicrophoneID) {
                            Text("No Microphone").tag(Optional<String>.none)
                            ForEach(coordinator.availableMicrophones) { mic in
                                Text(mic.name).tag(Optional(mic.id))
                            }
                        }
                        .labelsHidden()

                        // Live Mic Level Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule()
                                    .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: max(4, geo.size.width * CGFloat(coordinator.liveMicLevel)))
                            }
                        }
                        .frame(width: 56, height: 8)
                    }
                }

                GridRow {
                    Label("System Audio", systemImage: "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .medium))
                    HStack {
                        Toggle("Capture macOS System Audio Track", isOn: $coordinator.captureSystemAudio)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        Spacer()
                        Picker("Timer", selection: $coordinator.countdownOption) {
                            ForEach(CountdownOption.allCases) { opt in
                                Text(opt.label).tag(opt)
                            }
                        }
                        .frame(width: 145)
                    }
                }
            }
            .disabled(coordinator.isRecording)

            if let err = coordinator.statusErrorMessage {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            Divider()

            // Primary Recording Controls
            HStack(spacing: 10) {
                Button {
                    Task { await coordinator.refreshDevicesAndContent() }
                } label: {
                    Label("Refresh Sources", systemImage: "arrow.clockwise")
                        .font(.system(size: 12))
                }
                .disabled(coordinator.isRecording)

                Spacer()

                if coordinator.isCountingDown {
                    HStack(spacing: 10) {
                        Text("Starting in \(coordinator.countdownRemaining)…")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.orange)
                        Button("Cancel") {
                            coordinator.cancelCountdown()
                        }
                    }
                } else if coordinator.isRecording {
                    Button {
                        coordinator.togglePause()
                    } label: {
                        Label(
                            coordinator.isPaused ? "Resume" : "Pause",
                            systemImage: coordinator.isPaused ? "play.fill" : "pause.fill"
                        )
                    }

                    Button {
                        Task {
                            await coordinator.stopCaptureFlow()
                            onDismiss()
                        }
                    } label: {
                        Label("Finish & Open in Studio", systemImage: "stop.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        Task {
                            await coordinator.startCaptureFlow()
                        }
                    } label: {
                        Label("Start Recording (⌘⇧2)", systemImage: "record.circle")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .padding(16)
        .frame(width: 520)
        .task {
            await coordinator.refreshDevicesAndContent()
            permissions.refreshAllStatuses()
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let tenths = Int((seconds - floor(seconds)) * 10)
        return String(format: "%02d:%02d.%01d", mins, secs, tenths)
    }
}

// MARK: - Interactive Screen Region Selection Overlay Window

@MainActor
public final class RegionSelectionOverlayController {
    private var overlayWindow: NSWindow?

    public init() {}

    public func presentRegionSelector(
        initialRect: CGRect,
        onConfirm: @escaping (CGRect) -> Void
    ) {
        dismiss()
        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = InteractiveRegionSelectionView(
            initialRect: initialRect,
            screenSize: screen.frame.size,
            onConfirm: { [weak self] selected in
                onConfirm(selected)
                self?.dismiss()
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        self.overlayWindow = window
    }

    public func dismiss() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}

private struct InteractiveRegionSelectionView: View {
    @State var selectionRect: CGRect
    let screenSize: CGSize
    let onConfirm: (CGRect) -> Void
    let onCancel: () -> Void

    @State private var dragStart: CGPoint?

    init(
        initialRect: CGRect,
        screenSize: CGSize,
        onConfirm: @escaping (CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._selectionRect = State(initialValue: initialRect)
        self.screenSize = screenSize
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if dragStart == nil {
                                dragStart = value.startLocation
                            }
                            if let start = dragStart {
                                let minX = min(start.x, value.location.x)
                                let minY = min(start.y, value.location.y)
                                let w = max(120, abs(value.location.x - start.x))
                                let h = max(90, abs(value.location.y - start.y))
                                selectionRect = CGRect(x: round(minX), y: round(minY), width: round(w), height: round(h))
                            }
                        }
                        .onEnded { _ in
                            dragStart = nil
                        }
                )

            // Highlighted Region Box
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: selectionRect.width, height: selectionRect.height)
                .overlay(
                    Rectangle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .foregroundStyle(Color.white)
                )
                .position(x: selectionRect.midX, y: selectionRect.midY)

            // Control Pill inside/near Region
            HStack(spacing: 10) {
                Text("\(Int(selectionRect.width)) × \(Int(selectionRect.height))")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))

                Button("16:9 (1280×720)") {
                    selectionRect.size = CGSize(width: 1280, height: 720)
                }
                .controlSize(.small)

                Button("9:16 Vertical") {
                    selectionRect.size = CGSize(width: 540, height: 960)
                }
                .controlSize(.small)

                Button("1:1 Square") {
                    selectionRect.size = CGSize(width: 800, height: 800)
                }
                .controlSize(.small)

                Divider().frame(height: 16)

                Button("Cancel (Esc)") {
                    onCancel()
                }
                .controlSize(.small)

                Button("Confirm Region") {
                    onConfirm(selectionRect)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .position(
                x: min(max(300, selectionRect.midX), screenSize.width - 300),
                y: max(48, selectionRect.minY - 28)
            )
        }
    }
}
