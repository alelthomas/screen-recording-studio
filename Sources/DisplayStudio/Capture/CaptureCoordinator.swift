import Foundation
import CoreGraphics
import AppKit

public enum CountdownOption: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case threeSeconds = 3
    case fiveSeconds = 5

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .none: return "No Countdown"
        case .threeSeconds: return "3s Countdown"
        case .fiveSeconds: return "5s Countdown"
        }
    }
}

@MainActor
public final class CaptureCoordinator: ObservableObject {
    @Published public var targetMode: CaptureTargetMode = .fullDisplay
    @Published public var availableDisplays: [ShareableDisplayInfo] = []
    @Published public var selectedDisplayID: CGDirectDisplayID?
    @Published public var availableWindows: [ShareableWindowInfo] = []
    @Published public var selectedWindowID: CGWindowID?
    @Published public var customRegionRect: CGRect = CGRect(x: 160, y: 120, width: 1280, height: 720)

    @Published public var availableCameras: [CaptureDeviceInfo] = []
    @Published public var selectedCameraID: String?
    @Published public var availableMicrophones: [CaptureDeviceInfo] = []
    @Published public var selectedMicrophoneID: String?
    @Published public var captureSystemAudio: Bool = true
    @Published public var countdownOption: CountdownOption = .threeSeconds

    @Published public private(set) var isCountingDown: Bool = false
    @Published public private(set) var countdownRemaining: Int = 0
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var elapsedSeconds: TimeInterval = 0
    @Published public private(set) var liveMicLevel: Float = 0.05
    @Published public private(set) var liveWebcamCGImage: CGImage?
    @Published public var statusErrorMessage: String?

    public let telemetryMonitor = InputTelemetryMonitor()
    private let screenRecorder = ScreenRecorder()
    private let cameraAudioRecorder = CameraAudioRecorder()

    private var activeBundleURL: URL?
    private var recordingTimer: Timer?

    public var onRecordingCompleted: ((StudioProject, URL) -> Void)?

    public init() {
        cameraAudioRecorder.onMicrophoneLevel = { [weak self] level in
            Task { @MainActor [weak self] in
                self?.liveMicLevel = level
            }
        }
        cameraAudioRecorder.onWebcamFrame = { [weak self] cgImage in
            Task { @MainActor [weak self] in
                self?.liveWebcamCGImage = cgImage
            }
        }
    }

    public func refreshDevicesAndContent() async {
        let content = await ScreenRecorder.fetchShareableContent()
        availableDisplays = content.displays
        if selectedDisplayID == nil {
            selectedDisplayID = content.displays.first?.id
        }
        availableWindows = content.windows
        if selectedWindowID == nil {
            selectedWindowID = content.windows.first?.id
        }

        availableCameras = CameraAudioRecorder.availableCameras()
        availableMicrophones = CameraAudioRecorder.availableMicrophones()
        if selectedMicrophoneID == nil {
            selectedMicrophoneID = availableMicrophones.first?.id
        }
    }

    public func startCaptureFlow() async {
        guard !isRecording && !isCountingDown else { return }
        statusErrorMessage = nil

        if countdownOption.rawValue > 0 {
            isCountingDown = true
            countdownRemaining = countdownOption.rawValue
            while countdownRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !isCountingDown { return }
                countdownRemaining -= 1
            }
            isCountingDown = false
        }

        do {
            let bundleURL = try ProjectBundleManager.createNewBundleDirectory(title: "Screen Recording")
            self.activeBundleURL = bundleURL

            let screenVideoURL = bundleURL.appendingPathComponent("screen_raw.mov")
            let sysAudioURL = captureSystemAudio ? bundleURL.appendingPathComponent("system_audio.caf") : nil
            let webcamVideoURL = (selectedCameraID != nil) ? bundleURL.appendingPathComponent("webcam_raw.mov") : nil
            let micAudioURL = (selectedMicrophoneID != nil) ? bundleURL.appendingPathComponent("mic_audio.caf") : nil

            let resolvedBounds = try await screenRecorder.startRecording(
                mode: targetMode,
                displayID: selectedDisplayID,
                windowID: selectedWindowID,
                customRegion: targetMode == .customRegion ? customRegionRect : nil,
                captureSystemAudio: captureSystemAudio,
                videoOutputURL: screenVideoURL,
                systemAudioOutputURL: sysAudioURL
            )

            cameraAudioRecorder.startRecording(
                cameraID: selectedCameraID,
                microphoneID: selectedMicrophoneID,
                webcamOutputURL: webcamVideoURL,
                micOutputURL: micAudioURL
            )

            telemetryMonitor.startMonitoring(captureBounds: resolvedBounds)
            isRecording = true
            isPaused = false
            elapsedSeconds = 0

            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording, !self.isPaused else { return }
                    self.elapsedSeconds += 0.1
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.recordingTimer = timer
        } catch {
            statusErrorMessage = "Capture failed to start: \(error.localizedDescription). Check Screen Recording permission."
            isRecording = false
            isCountingDown = false
        }
    }

    public func togglePause() {
        guard isRecording else { return }
        isPaused.toggle()
        screenRecorder.setPaused(isPaused)
        cameraAudioRecorder.setPaused(isPaused)
        if isPaused {
            telemetryMonitor.pauseMonitoring()
        } else {
            telemetryMonitor.resumeMonitoring()
        }
    }

    public func cancelCountdown() {
        isCountingDown = false
        countdownRemaining = 0
    }

    public func stopCaptureFlow() async {
        guard isRecording else { return }
        recordingTimer?.invalidate()
        recordingTimer = nil
        isRecording = false
        isPaused = false

        let telemetry = telemetryMonitor.stopMonitoring()
        await screenRecorder.stopRecording()
        let micPeaks = await cameraAudioRecorder.stopRecording()

        guard let bundleURL = activeBundleURL else { return }

        let autoZooms = AutoZoomGenerator.generateZoomSegments(from: telemetry)
        let clips = [
            ClipSegment(
                label: "Recorded Screen",
                sourceStartTime: 0.0,
                sourceEndTime: telemetry.duration,
                speedMultiplier: 1.0
            )
        ]

        let downsampledWave = Self.downsampleWaveform(micPeaks, targetCount: 120, fallbackDuration: telemetry.duration)
        let sysWave = downsampledWave.map { max(0.08, $0 * 0.65) }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, HH:mm"

        let newProject = StudioProject(
            title: "Recording — \(dateFormatter.string(from: Date()))",
            aspectRatio: .widescreen16x9,
            background: BackgroundConfig(mode: .wallpaper, wallpaperPreset: .sequoiaSunrise),
            frameStyling: FrameStyling(),
            cursorSettings: CursorSettings(),
            webcamSettings: WebcamSettings(isEnabled: selectedCameraID != nil),
            audioSettings: AudioSettings(
                micVolume: 1.0,
                systemVolume: 0.85,
                isMicMuted: selectedMicrophoneID == nil,
                isSystemMuted: !captureSystemAudio,
                micWaveformSamples: downsampledWave,
                sysWaveformSamples: sysWave
            ),
            keystrokeSettings: KeystrokeOverlaySettings(isEnabled: true),
            captionStyle: CaptionStyleSettings(isEnabled: true),
            exportSettings: ExportSettings(),
            clips: clips,
            zoomSegments: autoZooms,
            speedRampSegments: [],
            captionSegments: [],
            telemetry: telemetry,
            screenVideoFilename: "screen_raw.mov",
            webcamVideoFilename: selectedCameraID != nil ? "webcam_raw.mov" : nil,
            systemAudioFilename: captureSystemAudio ? "system_audio.caf" : nil,
            micAudioFilename: selectedMicrophoneID != nil ? "mic_audio.caf" : nil
        )

        try? ProjectBundleManager.save(project: newProject, to: bundleURL)
        onRecordingCompleted?(newProject, bundleURL)
    }

    private static func downsampleWaveform(_ samples: [Float], targetCount: Int, fallbackDuration: TimeInterval) -> [Float] {
        guard !samples.isEmpty else {
            return (0..<targetCount).map { idx in
                let t = Double(idx) / Double(max(1, targetCount)) * fallbackDuration
                return Float(0.18 + 0.45 * abs(sin(t * 4.5) * cos(t * 2.3)))
            }
        }
        var out: [Float] = []
        out.reserveCapacity(targetCount)
        for i in 0..<targetCount {
            let idx = min(samples.count - 1, Int(Double(i) / Double(targetCount) * Double(samples.count)))
            out.append(samples[idx])
        }
        return out
    }
}
