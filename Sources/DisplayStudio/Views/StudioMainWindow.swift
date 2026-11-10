import Foundation
import SwiftUI
import AppKit

public struct StudioMainWindow: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                // Top Studio Toolbar
                StudioHeaderToolbar(appState: appState)

                Divider()

                // Middle Workspace: Center Stage Canvas + Right Inspector
                HStack(spacing: 0) {
                    PreviewCanvasView(appState: appState)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Divider()

                    InspectorSidebarView(appState: appState)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // Bottom Multi-Track Timeline Dock
                MultiTrackTimelineView(appState: appState)
            }

            // Floating Toast Notification Banner
            if let toast = appState.toastBannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.cyan)
                    Text(toast)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                .padding(.top, 56)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appState.showRecordingHUD) {
            RecordingLauncherHUDView(
                coordinator: appState.captureCoordinator,
                permissions: appState.permissions,
                onDismiss: { appState.showRecordingHUD = false },
                onOpenRegionSelector: {
                    appState.showRecordingHUD = false
                    appState.regionSelector.presentRegionSelector(
                        initialRect: appState.captureCoordinator.customRegionRect
                    ) { confirmedRect in
                        appState.captureCoordinator.customRegionRect = confirmedRect
                        appState.captureCoordinator.targetMode = .customRegion
                        appState.showRecordingHUD = true
                    }
                }
            )
        }
        .sheet(isPresented: $appState.showPermissionsSheet) {
            PermissionsOnboardingSheetView(
                permissions: appState.permissions,
                onDismiss: { appState.showPermissionsSheet = false }
            )
        }
        .sheet(isPresented: $appState.showExportSheet) {
            ExportSheetView(
                appState: appState,
                pipeline: appState.exportPipeline,
                cloudShare: appState.cloudShareService,
                onDismiss: { appState.showExportSheet = false }
            )
        }
    }
}

// MARK: - Top Studio Header Toolbar

private struct StudioHeaderToolbar: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 14) {
            // App Brand & Project Title
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 26, height: 26)
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                TextField("Project Title", text: $appState.project.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 215)
            }

            Divider().frame(height: 18)

            // Undo / Redo + Save
            HStack(spacing: 6) {
                Button {
                    appState.undo()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!appState.canUndo)
                .help("Undo (⌘Z)")

                Button {
                    appState.redo()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!appState.canRedo)
                .help("Redo (⇧⌘Z)")

                Button {
                    appState.saveProjectBundle()
                } label: {
                    Image(systemName: "externaldrive.badge.checkmark")
                }
                .help("Save .displaystudio Project Bundle (⌘S)")
            }
            .controlSize(.small)

            Divider().frame(height: 18)

            // Aspect Ratio Preset Picker
            Picker("Canvas", selection: $appState.project.aspectRatio) {
                ForEach(AspectRatioPreset.allCases) { ratio in
                    Text(ratio.rawValue).tag(ratio)
                }
            }
            .frame(width: 175)
            .controlSize(.small)

            // Canvas Zoom Selector
            Picker("Zoom", selection: $appState.canvasZoomMode) {
                Text("Fit").tag(1.0)
                Text("75%").tag(0.75)
                Text("50%").tag(0.5)
            }
            .frame(width: 105)
            .controlSize(.small)

            Spacer()

            // Record New / Permissions / Share / Export CTAs
            HStack(spacing: 8) {
                Button {
                    appState.showPermissionsSheet = true
                } label: {
                    Label("Permissions", systemImage: "checkmark.shield")
                        .font(.system(size: 11, weight: .medium))
                }
                .controlSize(.small)

                Button {
                    appState.showRecordingHUD = true
                } label: {
                    Label(
                        appState.captureCoordinator.isRecording ? "Recording…" : "New Recording",
                        systemImage: "record.circle"
                    )
                    .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)

                Button {
                    Task {
                        await appState.cloudShareService.exportAndCopyShareLink(
                            project: appState.project,
                            bundleURL: appState.bundleURL,
                            exportPipeline: appState.exportPipeline
                        )
                        if let link = appState.cloudShareService.latestShareURL {
                            appState.showToast("Copied Share Link: \(link)")
                        }
                    }
                } label: {
                    Label(
                        appState.cloudShareService.isSharing ? "Sharing…" : "Share Link",
                        systemImage: "link"
                    )
                    .font(.system(size: 12, weight: .medium))
                }
                .controlSize(.small)
                .disabled(appState.cloudShareService.isSharing)

                Button {
                    appState.showExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(nsColor: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.14, alpha: 1.0)))
    }
}
