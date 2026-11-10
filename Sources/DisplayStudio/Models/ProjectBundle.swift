import Foundation
import CoreGraphics

// MARK: - DisplayStudio Project Model

public struct StudioProject: Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var createdAt: Date
    public var updatedAt: Date
    public var aspectRatio: AspectRatioPreset
    public var background: BackgroundConfig
    public var frameStyling: FrameStyling
    public var cursorSettings: CursorSettings
    public var webcamSettings: WebcamSettings
    public var audioSettings: AudioSettings
    public var keystrokeSettings: KeystrokeOverlaySettings
    public var captionStyle: CaptionStyleSettings
    public var exportSettings: ExportSettings

    public var clips: [ClipSegment]
    public var zoomSegments: [ZoomSegment]
    public var speedRampSegments: [SpeedRampSegment]
    public var captionSegments: [CaptionSegment]

    public var telemetry: RecordingTelemetry

    /// Relative filenames inside `.displaystudio` bundle directory
    public var screenVideoFilename: String
    public var webcamVideoFilename: String?
    public var systemAudioFilename: String?
    public var micAudioFilename: String?

    public init(
        id: UUID = UUID(),
        title: String = "Product Walkthrough",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        aspectRatio: AspectRatioPreset = .widescreen16x9,
        background: BackgroundConfig = BackgroundConfig(),
        frameStyling: FrameStyling = FrameStyling(),
        cursorSettings: CursorSettings = CursorSettings(),
        webcamSettings: WebcamSettings = WebcamSettings(),
        audioSettings: AudioSettings = AudioSettings(),
        keystrokeSettings: KeystrokeOverlaySettings = KeystrokeOverlaySettings(),
        captionStyle: CaptionStyleSettings = CaptionStyleSettings(),
        exportSettings: ExportSettings = ExportSettings(),
        clips: [ClipSegment] = [],
        zoomSegments: [ZoomSegment] = [],
        speedRampSegments: [SpeedRampSegment] = [],
        captionSegments: [CaptionSegment] = [],
        telemetry: RecordingTelemetry = RecordingTelemetry(),
        screenVideoFilename: String = "screen_raw.mov",
        webcamVideoFilename: String? = "webcam_raw.mov",
        systemAudioFilename: String? = "system_audio.caf",
        micAudioFilename: String? = "mic_audio.caf"
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.aspectRatio = aspectRatio
        self.background = background
        self.frameStyling = frameStyling
        self.cursorSettings = cursorSettings
        self.webcamSettings = webcamSettings
        self.audioSettings = audioSettings
        self.keystrokeSettings = keystrokeSettings
        self.captionStyle = captionStyle
        self.exportSettings = exportSettings
        self.clips = clips
        self.zoomSegments = zoomSegments
        self.speedRampSegments = speedRampSegments
        self.captionSegments = captionSegments
        self.telemetry = telemetry
        self.screenVideoFilename = screenVideoFilename
        self.webcamVideoFilename = webcamVideoFilename
        self.systemAudioFilename = systemAudioFilename
        self.micAudioFilename = micAudioFilename
    }

    public var totalTimelineDuration: TimeInterval {
        if clips.isEmpty {
            return max(1.0, telemetry.duration)
        }
        return max(0.5, clips.reduce(0.0) { $0 + $1.timelineDuration })
    }

    /// Maps a timeline playhead timestamp to the underlying raw recording source timestamp and instantaneous playback rate.
    public func mapTimelineToSourceTime(_ timelineTime: TimeInterval) -> (sourceTime: TimeInterval, speedMultiplier: Double, isMuted: Bool) {
        guard !clips.isEmpty else {
            let speed = speedMultiplier(atSourceTime: timelineTime)
            return (min(max(0, timelineTime), telemetry.duration), speed, false)
        }

        var accumulated: TimeInterval = 0
        for clip in clips {
            let clipTimelineDur = clip.timelineDuration
            if timelineTime <= accumulated + clipTimelineDur {
                let localOffset = max(0, timelineTime - accumulated)
                let baseSourceTime = clip.sourceStartTime + localOffset * clip.speedMultiplier
                let rampMult = speedMultiplier(atSourceTime: baseSourceTime)
                return (
                    min(clip.sourceEndTime, baseSourceTime),
                    clip.speedMultiplier * rampMult,
                    clip.isMuted
                )
            }
            accumulated += clipTimelineDur
        }

        if let last = clips.last {
            return (last.sourceEndTime, last.speedMultiplier, last.isMuted)
        }
        return (timelineTime, 1.0, false)
    }

    public func speedMultiplier(atSourceTime time: TimeInterval) -> Double {
        for ramp in speedRampSegments where time >= ramp.startTime && time <= ramp.endTime {
            let ease = max(0.05, min(ramp.easeDuration, (ramp.endTime - ramp.startTime) * 0.4))
            if time < ramp.startTime + ease {
                let t = (time - ramp.startTime) / ease
                let smooth = t * t * (3.0 - 2.0 * t)
                return 1.0 + (ramp.speedMultiplier - 1.0) * smooth
            } else if time > ramp.endTime - ease {
                let t = (ramp.endTime - time) / ease
                let smooth = t * t * (3.0 - 2.0 * t)
                return 1.0 + (ramp.speedMultiplier - 1.0) * smooth
            }
            return ramp.speedMultiplier
        }
        return 1.0
    }
}

// MARK: - .displaystudio Bundle Persistence & Demo Factory

public enum ProjectBundleManager {
    public static let bundleExtension = "displaystudio"

    public static func defaultProjectsDirectory() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = movies.appendingPathComponent("DisplayStudioProjects", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static func createNewBundleDirectory(title: String) throws -> URL {
        let safeTitle = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let timestamp = Int(Date().timeIntervalSince1970)
        let folderName = "\(safeTitle)-\(timestamp).\(bundleExtension)"
        let url = defaultProjectsDirectory().appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static func save(project: StudioProject, to bundleURL: URL) throws {
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let projectData = try encoder.encode(project)
        let projectFile = bundleURL.appendingPathComponent("project.json")
        try projectData.write(to: projectFile, options: .atomic)

        let telemetryData = try encoder.encode(project.telemetry)
        let telemetryFile = bundleURL.appendingPathComponent("telemetry.json")
        try telemetryData.write(to: telemetryFile, options: .atomic)
    }

    public static func load(from bundleURL: URL) throws -> StudioProject {
        let projectFile = bundleURL.appendingPathComponent("project.json")
        let data = try Data(contentsOf: projectFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StudioProject.self, from: data)
    }

    /// Generates a rich interactive demo project with 120Hz cursor telemetry, click clusters,
    /// shortcuts, typing bursts, waveforms, zoom keyframes, speed ramps, and captions.
    public static func makeInteractiveDemoProject() -> StudioProject {
        let duration: TimeInterval = 14.0
        let sampleRate = 120
        let totalSamples = Int(duration * Double(sampleRate))

        // Key waypoints simulating a user navigating a macOS IDE / dashboard
        let waypoints: [(time: Double, point: CGPoint, style: CursorStyle)] = [
            (0.0, CGPoint(x: 0.50, y: 0.52), .arrow),
            (1.2, CGPoint(x: 0.18, y: 0.22), .pointingHand),  // Sidebar navigation click
            (2.8, CGPoint(x: 0.20, y: 0.34), .pointingHand),  // Second sidebar item
            (4.3, CGPoint(x: 0.54, y: 0.28), .iBeam),         // Search bar click + typing burst
            (6.8, CGPoint(x: 0.58, y: 0.45), .arrow),         // Inspecting code editor
            (8.2, CGPoint(x: 0.82, y: 0.18), .pointingHand),  // Top right "Deploy / Export" button
            (10.0, CGPoint(x: 0.64, y: 0.68), .pointingHand), // Modal confirmation click
            (12.2, CGPoint(x: 0.48, y: 0.50), .arrow),
            (14.0, CGPoint(x: 0.50, y: 0.50), .arrow)
        ]

        var samples: [CursorSample] = []
        samples.reserveCapacity(totalSamples)

        for i in 0...totalSamples {
            let t = Double(i) / Double(sampleRate)
            // Find surrounding waypoints
            var prev = waypoints.first!
            var next = waypoints.last!
            for idx in 0..<(waypoints.count - 1) {
                if t >= waypoints[idx].time && t <= waypoints[idx + 1].time {
                    prev = waypoints[idx]
                    next = waypoints[idx + 1]
                    break
                }
            }
            let span = max(0.001, next.time - prev.time)
            let localT = min(1.0, max(0.0, (t - prev.time) / span))
            // Smooth S-curve with realistic micro-hand jitter before spring smoothing
            let ease = localT * localT * (3.0 - 2.0 * localT)
            let jitterX = sin(t * 29.0) * 0.0025 * (localT > 0.1 && localT < 0.9 ? 1.0 : 0.15)
            let jitterY = cos(t * 37.0) * 0.0025 * (localT > 0.1 && localT < 0.9 ? 1.0 : 0.15)
            let px = min(0.98, max(0.02, prev.point.x + (next.point.x - prev.point.x) * ease + jitterX))
            let py = min(0.98, max(0.02, prev.point.y + (next.point.y - prev.point.y) * ease + jitterY))
            let style = localT > 0.7 ? next.style : prev.style
            samples.append(CursorSample(timestamp: t, normalizedPos: CGPoint(x: px, y: py), cursorType: style))
        }

        let clicks: [ClickEvent] = [
            ClickEvent(timestamp: 1.25, button: .left, phase: .down, normalizedPos: CGPoint(x: 0.18, y: 0.22)),
            ClickEvent(timestamp: 1.36, button: .left, phase: .up, normalizedPos: CGPoint(x: 0.18, y: 0.22)),
            ClickEvent(timestamp: 2.82, button: .left, phase: .down, normalizedPos: CGPoint(x: 0.20, y: 0.34)),
            ClickEvent(timestamp: 2.94, button: .left, phase: .up, normalizedPos: CGPoint(x: 0.20, y: 0.34)),
            ClickEvent(timestamp: 4.35, button: .left, phase: .down, normalizedPos: CGPoint(x: 0.54, y: 0.28)),
            ClickEvent(timestamp: 4.46, button: .left, phase: .up, normalizedPos: CGPoint(x: 0.54, y: 0.28)),
            ClickEvent(timestamp: 8.24, button: .left, phase: .down, normalizedPos: CGPoint(x: 0.82, y: 0.18)),
            ClickEvent(timestamp: 8.36, button: .left, phase: .up, normalizedPos: CGPoint(x: 0.82, y: 0.18)),
            ClickEvent(timestamp: 10.05, button: .left, phase: .down, normalizedPos: CGPoint(x: 0.64, y: 0.68)),
            ClickEvent(timestamp: 10.18, button: .left, phase: .up, normalizedPos: CGPoint(x: 0.64, y: 0.68))
        ]

        let keystrokes: [KeystrokeEvent] = [
            KeystrokeEvent(
                timestamp: 1.45,
                characters: "k",
                displayLabel: "⌘ K",
                keyCode: 40,
                modifiers: [.command],
                isShortcut: true,
                cursorNormalizedPos: CGPoint(x: 0.18, y: 0.22)
            ),
            KeystrokeEvent(
                timestamp: 4.65,
                characters: "ScreenCaptureKit",
                displayLabel: "⌨︎ \"ScreenCaptureKit\"",
                keyCode: 1,
                modifiers: [],
                isShortcut: false,
                cursorNormalizedPos: CGPoint(x: 0.54, y: 0.28)
            ),
            KeystrokeEvent(
                timestamp: 6.20,
                characters: "p",
                displayLabel: "⌘ ⇧ P",
                keyCode: 35,
                modifiers: [.command, .shift],
                isShortcut: true,
                cursorNormalizedPos: CGPoint(x: 0.56, y: 0.38)
            ),
            KeystrokeEvent(
                timestamp: 8.40,
                characters: "e",
                displayLabel: "⌘ E  Export 4K",
                keyCode: 14,
                modifiers: [.command],
                isShortcut: true,
                cursorNormalizedPos: CGPoint(x: 0.82, y: 0.18)
            ),
            KeystrokeEvent(
                timestamp: 10.30,
                characters: "\r",
                displayLabel: "⏎ Return",
                keyCode: 36,
                modifiers: [],
                isShortcut: true,
                cursorNormalizedPos: CGPoint(x: 0.64, y: 0.68)
            )
        ]

        let telemetry = RecordingTelemetry(
            duration: duration,
            sourceSize: CGSize(width: 1920, height: 1080),
            sampleRateHz: sampleRate,
            cursorSamples: samples,
            clickEvents: clicks,
            scrollEvents: [],
            keystrokeEvents: keystrokes
        )

        let zooms: [ZoomSegment] = [
            ZoomSegment(
                startTime: 0.95,
                endTime: 3.45,
                zoomDepth: 2.15,
                mode: .followCursor,
                transitionPreset: .quick,
                isAutoGenerated: true
            ),
            ZoomSegment(
                startTime: 4.10,
                endTime: 6.70,
                zoomDepth: 2.35,
                mode: .followCursor,
                transitionPreset: .snappy,
                isAutoGenerated: true
            ),
            ZoomSegment(
                startTime: 7.90,
                endTime: 11.20,
                zoomDepth: 2.05,
                mode: .followCursor,
                transitionPreset: .mellow,
                isAutoGenerated: true
            )
        ]

        let speedRamps: [SpeedRampSegment] = [
            SpeedRampSegment(startTime: 6.75, endTime: 7.85, speedMultiplier: 2.0, easeDuration: 0.25)
        ]

        let clips: [ClipSegment] = [
            ClipSegment(label: "Main Walkthrough", sourceStartTime: 0.0, sourceEndTime: duration, speedMultiplier: 1.0)
        ]

        let captions: [CaptionSegment] = [
            CaptionSegment(
                startTime: 0.4,
                endTime: 3.6,
                text: "Welcome to Display Studio — automatic spring-physics cursor zoom.",
                words: [
                    CaptionWord(word: "Welcome", startTime: 0.4, endTime: 0.85),
                    CaptionWord(word: "to", startTime: 0.85, endTime: 1.05),
                    CaptionWord(word: "Display", startTime: 1.05, endTime: 1.50),
                    CaptionWord(word: "Studio", startTime: 1.50, endTime: 1.95),
                    CaptionWord(word: "—", startTime: 1.95, endTime: 2.05),
                    CaptionWord(word: "automatic", startTime: 2.05, endTime: 2.55),
                    CaptionWord(word: "spring-physics", startTime: 2.55, endTime: 3.15),
                    CaptionWord(word: "cursor", startTime: 3.15, endTime: 3.40),
                    CaptionWord(word: "zoom.", startTime: 3.40, endTime: 3.60)
                ]
            ),
            CaptionSegment(
                startTime: 4.0,
                endTime: 7.4,
                text: "Every click and typing burst is captured non-destructively at 120Hz.",
                words: [
                    CaptionWord(word: "Every", startTime: 4.0, endTime: 4.4),
                    CaptionWord(word: "click", startTime: 4.4, endTime: 4.8),
                    CaptionWord(word: "and", startTime: 4.8, endTime: 5.0),
                    CaptionWord(word: "typing", startTime: 5.0, endTime: 5.4),
                    CaptionWord(word: "burst", startTime: 5.4, endTime: 5.8),
                    CaptionWord(word: "is", startTime: 5.8, endTime: 6.0),
                    CaptionWord(word: "captured", startTime: 6.0, endTime: 6.5),
                    CaptionWord(word: "non-destructively", startTime: 6.5, endTime: 7.05),
                    CaptionWord(word: "at", startTime: 7.05, endTime: 7.15),
                    CaptionWord(word: "120Hz.", startTime: 7.15, endTime: 7.4)
                ]
            ),
            CaptionSegment(
                startTime: 7.8,
                endTime: 11.8,
                text: "Customize wallpapers, motion blur, webcam PiP, and export in 4K 60fps.",
                words: [
                    CaptionWord(word: "Customize", startTime: 7.8, endTime: 8.3),
                    CaptionWord(word: "wallpapers,", startTime: 8.3, endTime: 8.9),
                    CaptionWord(word: "motion", startTime: 8.9, endTime: 9.25),
                    CaptionWord(word: "blur,", startTime: 9.25, endTime: 9.6),
                    CaptionWord(word: "webcam", startTime: 9.6, endTime: 10.0),
                    CaptionWord(word: "PiP,", startTime: 10.0, endTime: 10.3),
                    CaptionWord(word: "and", startTime: 10.3, endTime: 10.5),
                    CaptionWord(word: "export", startTime: 10.5, endTime: 10.95),
                    CaptionWord(word: "in", startTime: 10.95, endTime: 11.15),
                    CaptionWord(word: "4K", startTime: 11.15, endTime: 11.4),
                    CaptionWord(word: "60fps.", startTime: 11.4, endTime: 11.8)
                ]
            )
        ]

        // Generate synthetic audio waveforms for Mic & System Audio tracks
        var micWave: [Float] = []
        var sysWave: [Float] = []
        for idx in 0..<140 {
            let phase = Double(idx) / 140.0 * duration
            let speaking = (phase >= 0.4 && phase <= 3.6) || (phase >= 4.0 && phase <= 7.4) || (phase >= 7.8 && phase <= 11.8)
            let micAmp = speaking ? Float(0.35 + 0.55 * abs(sin(phase * 9.3) * cos(phase * 4.1))) : Float(0.05)
            let sysAmp = Float(0.18 + 0.35 * abs(sin(phase * 5.7))) * (speaking ? 0.45 : 1.0)
            micWave.append(micAmp)
            sysWave.append(sysAmp)
        }

        let audio = AudioSettings(
            micVolume: 1.0,
            systemVolume: 0.80,
            isMicMuted: false,
            isSystemMuted: false,
            voiceIsolation: true,
            autoDuckSystemAudio: true,
            duckingAmountDB: -12.0,
            micWaveformSamples: micWave,
            sysWaveformSamples: sysWave
        )

        return StudioProject(
            title: "Display Studio — Interactive Demo",
            aspectRatio: .widescreen16x9,
            background: BackgroundConfig(mode: .wallpaper, wallpaperPreset: .sequoiaSunrise),
            frameStyling: FrameStyling(paddingRatio: 0.085, cornerRadius: 20, shadowOpacity: 0.58, shadowRadius: 40, shadowOffsetY: 18),
            cursorSettings: CursorSettings(scale: 1.75, springPreset: .smooth, showClickRipple: true, motionBlurIntensity: 0.65),
            webcamSettings: WebcamSettings(isEnabled: true, shape: .squircle, corner: .bottomRight, scale: 0.21),
            audioSettings: audio,
            keystrokeSettings: KeystrokeOverlaySettings(isEnabled: true, shortcutsOnly: false),
            captionStyle: CaptionStyleSettings(isEnabled: true),
            exportSettings: ExportSettings(format: .mp4HEVC, resolution: .p1080, fps: 60, quality: .high),
            clips: clips,
            zoomSegments: zooms,
            speedRampSegments: speedRamps,
            captionSegments: captions,
            telemetry: telemetry
        )
    }
}
