import Foundation
import AppKit
import CoreGraphics
import AVFoundation
import Speech
import ApplicationServices

@MainActor
public final class PermissionManager: ObservableObject {
    @Published public private(set) var hasScreenRecordingPermission: Bool = false
    @Published public private(set) var hasAccessibilityPermission: Bool = false
    @Published public private(set) var hasCameraPermission: Bool = false
    @Published public private(set) var hasMicrophonePermission: Bool = false
    @Published public private(set) var hasSpeechPermission: Bool = false

    public init() {
        refreshAllStatuses()
    }

    public func refreshAllStatuses() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        hasAccessibilityPermission = AXIsProcessTrusted()
        hasCameraPermission = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        hasMicrophonePermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        hasSpeechPermission = SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public func requestScreenRecordingPermission() {
        let granted = CGRequestScreenCaptureAccess()
        hasScreenRecordingPermission = granted
        if !granted {
            openSystemSettings(anchor: "Privacy_ScreenCapture")
        }
    }

    public func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasAccessibilityPermission = trusted
        if !trusted {
            openSystemSettings(anchor: "Privacy_Accessibility")
        }
    }

    public func requestCameraPermission() {
        let current = AVCaptureDevice.authorizationStatus(for: .video)
        if current == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.hasCameraPermission = granted
                }
            }
        } else if current == .authorized {
            hasCameraPermission = true
        } else {
            openSystemSettings(anchor: "Privacy_Camera")
        }
    }

    public func requestMicrophonePermission() {
        let current = AVCaptureDevice.authorizationStatus(for: .audio)
        if current == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor [weak self] in
                    self?.hasMicrophonePermission = granted
                }
            }
        } else if current == .authorized {
            hasMicrophonePermission = true
        } else {
            openSystemSettings(anchor: "Privacy_Microphone")
        }
    }

    public func requestSpeechPermission() {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .notDetermined {
            SFSpeechRecognizer.requestAuthorization { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.hasSpeechPermission = (status == .authorized)
                }
            }
        } else if current == .authorized {
            hasSpeechPermission = true
        } else {
            openSystemSettings(anchor: "Privacy_SpeechRecognition")
        }
    }

    public func openSystemSettings(anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
