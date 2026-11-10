import Foundation
import SwiftUI
import AppKit

@main
public struct DisplayStudioApp: App {
    @StateObject private var appState = AppState()

    public init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    public var body: some Scene {
        WindowGroup("Display Studio") {
            StudioMainWindow(appState: appState)
                .frame(minWidth: 1180, minHeight: 760)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Screen Recording…") {
                    appState.showRecordingHUD = true
                }
                .keyboardShortcut("2", modifiers: [.command, .shift])

                Button("Reset to Interactive Demo Project") {
                    appState.loadDemoProject()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button("Save .displaystudio Bundle") {
                    appState.saveProjectBundle()
                }
                .keyboardShortcut("s", modifiers: [.command])
            }

            CommandMenu("Timeline") {
                Button(appState.isPlaying ? "Pause Playback" : "Start Playback") {
                    appState.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])

                Divider()

                Button("Add Zoom Keyframe at Playhead") {
                    appState.addZoomSegmentAtPlayhead()
                }
                .keyboardShortcut("j", modifiers: [.command])

                Button("Split Clip at Playhead") {
                    appState.splitClipAtPlayhead()
                }
                .keyboardShortcut("b", modifiers: [.command])

                Button("Add 2x Speed Ramp at Playhead") {
                    appState.addSpeedRampAtPlayhead(multiplier: 2.0)
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Re-Generate Auto-Zooms from Clicks") {
                    appState.regenerateAutoZooms()
                }

                Divider()

                Button("Export Video…") {
                    appState.showExportSheet = true
                }
                .keyboardShortcut("e", modifiers: [.command])
            }
        }

        MenuBarExtra(
            appState.captureCoordinator.isRecording ? "REC • Display Studio" : "Display Studio",
            systemImage: appState.captureCoordinator.isRecording ? "record.circle.fill" : "record.circle"
        ) {
            if appState.captureCoordinator.isRecording {
                Text(String(format: "Recording: %.1fs", appState.captureCoordinator.elapsedSeconds))
                Button(appState.captureCoordinator.isPaused ? "Resume Recording" : "Pause Recording") {
                    appState.captureCoordinator.togglePause()
                }
                Button("Stop & Open in Studio") {
                    Task {
                        await appState.captureCoordinator.stopCaptureFlow()
                    }
                }
            } else {
                Button("New Screen Recording (⌘⇧2)") {
                    appState.showRecordingHUD = true
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Button("Export Current Project (⌘E)") {
                    appState.showExportSheet = true
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            }
            Divider()
            Button("Quit Display Studio") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
