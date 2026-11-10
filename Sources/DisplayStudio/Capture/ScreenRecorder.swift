import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CoreVideo

public enum CaptureTargetMode: String, CaseIterable, Identifiable, Sendable {
    case fullDisplay = "Full Screen"
    case window = "App Window"
    case customRegion = "Custom Region"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .fullDisplay: return "display"
        case .window: return "macwindow"
        case .customRegion: return "viewfinder.rectangular"
        }
    }
}

public struct ShareableWindowInfo: Identifiable, Equatable, Hashable, Sendable {
    public var id: CGWindowID
    public var title: String
    public var appName: String
    public var frame: CGRect

    public init(id: CGWindowID, title: String, appName: String, frame: CGRect) {
        self.id = id
        self.title = title
        self.appName = appName
        self.frame = frame
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(appName)
    }
}

public struct ShareableDisplayInfo: Identifiable, Equatable, Hashable, Sendable {
    public var id: CGDirectDisplayID
    public var width: Int
    public var height: Int
    public var frame: CGRect

    public init(id: CGDirectDisplayID, width: Int, height: Int, frame: CGRect) {
        self.id = id
        self.width = width
        self.height = height
        self.frame = frame
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(width)
        hasher.combine(height)
    }

    public var displayName: String {
        "Display \(id) (\(width)×\(height))"
    }
}

public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let videoQueue = DispatchQueue(label: "com.displaystudio.screenrecorder.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.displaystudio.screenrecorder.audio", qos: .userInitiated)

    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriter: AVAssetWriter?
    private var audioWriterInput: AVAssetWriterInput?

    private var isWritingSessionStarted = false
    private var isAudioSessionStarted = false
    private var isPaused = false
    private var capturedBounds: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    public override init() {
        super.init()
    }

    // MARK: - Enumerate Displays & Windows

    public static func fetchShareableContent() async -> (displays: [ShareableDisplayInfo], windows: [ShareableWindowInfo]) {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let displays = content.displays.map {
                ShareableDisplayInfo(id: $0.displayID, width: $0.width, height: $0.height, frame: $0.frame)
            }
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let windows = content.windows.compactMap { win -> ShareableWindowInfo? in
                guard let app = win.owningApplication,
                      app.processID != currentPID,
                      win.frame.width >= 160,
                      win.frame.height >= 120 else {
                    return nil
                }
                let title = (win.title?.isEmpty == false) ? win.title! : app.applicationName
                return ShareableWindowInfo(
                    id: win.windowID,
                    title: title,
                    appName: app.applicationName,
                    frame: win.frame
                )
            }
            return (displays, windows)
        } catch {
            return ([], [])
        }
    }

    // MARK: - Start / Pause / Stop ScreenCaptureKit Stream

    public func startRecording(
        mode: CaptureTargetMode,
        displayID: CGDirectDisplayID?,
        windowID: CGWindowID?,
        customRegion: CGRect?,
        captureSystemAudio: Bool,
        videoOutputURL: URL,
        systemAudioOutputURL: URL?
    ) async throws -> CGRect {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let excludedApps = content.applications.filter { $0.processID == currentPID }

        let filter: SCContentFilter
        let targetSize: CGSize
        let resolvedBounds: CGRect

        switch mode {
        case .window:
            if let windowID, let targetWindow = content.windows.first(where: { $0.windowID == windowID }) {
                filter = SCContentFilter(desktopIndependentWindow: targetWindow)
                targetSize = CGSize(width: max(320, targetWindow.frame.width * 2), height: max(240, targetWindow.frame.height * 2))
                resolvedBounds = targetWindow.frame
            } else if let firstDisplay = content.displays.first {
                filter = SCContentFilter(display: firstDisplay, excludingApplications: excludedApps, exceptingWindows: [])
                targetSize = CGSize(width: firstDisplay.width * 2, height: firstDisplay.height * 2)
                resolvedBounds = firstDisplay.frame
            } else {
                throw NSError(domain: "DisplayStudio.ScreenRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "No capture display found"])
            }

        case .customRegion, .fullDisplay:
            guard let targetDisplay = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw NSError(domain: "DisplayStudio.ScreenRecorder", code: -2, userInfo: [NSLocalizedDescriptionKey: "No active display available"])
            }
            filter = SCContentFilter(display: targetDisplay, excludingApplications: excludedApps, exceptingWindows: [])
            if mode == .customRegion, let region = customRegion, region.width > 40, region.height > 40 {
                targetSize = CGSize(width: round(region.width * 2), height: round(region.height * 2))
                resolvedBounds = region
            } else {
                targetSize = CGSize(width: targetDisplay.width, height: targetDisplay.height)
                resolvedBounds = targetDisplay.frame
            }
        }

        self.capturedBounds = resolvedBounds

        let config = SCStreamConfiguration()
        config.width = max(640, Int(targetSize.width) & ~1)
        config.height = max(360, Int(targetSize.height) & ~1)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_32BGRA
        // CRITICAL: Hide native system cursor in raw video buffer so studio renders vector cursor non-destructively
        config.showsCursor = false
        config.capturesAudio = captureSystemAudio
        config.sampleRate = 48000
        config.channelCount = 2

        if mode == .customRegion, let region = customRegion, region.width > 40, region.height > 40 {
            config.sourceRect = region
        }

        // Configure AVAssetWriter for raw screen video
        try? FileManager.default.removeItem(at: videoOutputURL)
        let vWriter = try AVAssetWriter(outputURL: videoOutputURL, fileType: .mov)
        let vSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: config.width,
            AVVideoHeightKey: config.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: config.width * config.height * 8,
                AVVideoExpectedSourceFrameRateKey: 60
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: vSettings)
        vInput.expectsMediaDataInRealTime = true
        if vWriter.canAdd(vInput) {
            vWriter.add(vInput)
        }
        vWriter.startWriting()
        self.videoWriter = vWriter
        self.videoWriterInput = vInput
        self.isWritingSessionStarted = false

        // Configure AVAssetWriter for system audio if enabled
        if captureSystemAudio, let sysAudioURL = systemAudioOutputURL {
            try? FileManager.default.removeItem(at: sysAudioURL)
            let aWriter = try AVAssetWriter(outputURL: sysAudioURL, fileType: .caf)
            let aSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
            aInput.expectsMediaDataInRealTime = true
            if aWriter.canAdd(aInput) {
                aWriter.add(aInput)
            }
            aWriter.startWriting()
            self.audioWriter = aWriter
            self.audioWriterInput = aInput
            self.isAudioSessionStarted = false
        }

        self.isPaused = false
        let scStream = SCStream(filter: filter, configuration: config, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        if captureSystemAudio {
            try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        try await scStream.startCapture()
        self.stream = scStream
        return resolvedBounds
    }

    public func setPaused(_ paused: Bool) {
        videoQueue.async { [weak self] in
            self?.isPaused = paused
        }
    }

    public func stopRecording() async {
        if let activeStream = stream {
            try? await activeStream.stopCapture()
            stream = nil
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            videoQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.videoWriterInput?.markAsFinished()
                if let writer = self.videoWriter, writer.status == .writing {
                    writer.finishWriting {
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
                self.videoWriter = nil
                self.videoWriterInput = nil
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            audioQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                self.audioWriterInput?.markAsFinished()
                if let writer = self.audioWriter, writer.status == .writing {
                    writer.finishWriting {
                        continuation.resume()
                    }
                } else {
                    continuation.resume()
                }
                self.audioWriter = nil
                self.audioWriterInput = nil
            }
        }
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferIsValid(sampleBuffer), !isPaused else { return }

        switch type {
        case .screen:
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  status == .complete else {
                return
            }
            guard let writer = videoWriter, let input = videoWriterInput else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !isWritingSessionStarted {
                writer.startSession(atSourceTime: pts)
                isWritingSessionStarted = true
            }
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }

        case .audio:
            guard let writer = audioWriter, let input = audioWriterInput else { return }
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if !isAudioSessionStarted {
                writer.startSession(atSourceTime: pts)
                isAudioSessionStarted = true
            }
            if input.isReadyForMoreMediaData {
                input.append(sampleBuffer)
            }

        @unknown default:
            break
        }
    }
}
