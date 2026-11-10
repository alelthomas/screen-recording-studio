import Foundation
import SwiftUI
import Combine

public enum InspectorTab: String, CaseIterable, Identifiable, Sendable {
    case background = "Background"
    case cursorZoom = "Cursor & Zoom"
    case webcamAudio = "Webcam & Audio"
    case captionsKeys = "Captions & Keys"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .background: return "photo.artframe"
        case .cursorZoom: return "cursorarrow.motionlines"
        case .webcamAudio: return "person.crop.rectangle"
        case .captionsKeys: return "captions.bubble"
        }
    }
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var project: StudioProject {
        didSet {
            recomputeCurrentFrame()
        }
    }
    @Published public var bundleURL: URL?

    // Selection & UI state
    @Published public var selectedInspectorTab: InspectorTab = .background
    @Published public var selectedZoomSegmentID: UUID?
    @Published public var selectedClipID: UUID?
    @Published public var selectedSpeedRampID: UUID?
    @Published public var selectedCaptionID: UUID?

    @Published public var canvasZoomMode: Double = 1.0 // 1.0 = Fit, 0.5 = 50%, 1.25 = 125%
    @Published public var timelineZoomScale: Double = 90.0 // pixels per second

    // Playback state
    @Published public var isPlaying: Bool = false
    @Published public var playheadTime: TimeInterval = 0.0 {
        didSet {
            recomputeCurrentFrame()
        }
    }
    @Published public private(set) var currentFrameState: EvaluatedFrameState = EvaluatedFrameState()
    @Published public private(set) var currentPreviewImage: CGImage?

    // Modals & Popovers
    @Published public var showRecordingHUD: Bool = false
    @Published public var showPermissionsSheet: Bool = false
    @Published public var showExportSheet: Bool = false
    @Published public var toastBannerMessage: String?

    // Services
    public let permissions = PermissionManager()
    public let captureCoordinator = CaptureCoordinator()
    public let captionService = SpeechCaptionService()
    public let exportPipeline = VideoExportPipeline()
    public let cloudShareService = CloudShareService()
    public let regionSelector = RegionSelectionOverlayController()

    private let springSolver = SpringPhysicsSolver()
    private let compositor = MetalCompositor()
    private var playbackTimer: Timer?

    // Undo / Redo Stacks
    private var undoStack: [StudioProject] = []
    private var redoStack: [StudioProject] = []

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public init() {
        let initialProject = ProjectBundleManager.makeInteractiveDemoProject()
        self.project = initialProject
        self.selectedZoomSegmentID = initialProject.zoomSegments.first?.id
        self.selectedClipID = initialProject.clips.first?.id

        captureCoordinator.onRecordingCompleted = { [weak self] newProject, url in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recordUndoSnapshot()
                self.bundleURL = url
                self.project = newProject
                self.playheadTime = 0
                self.selectedZoomSegmentID = newProject.zoomSegments.first?.id
                self.selectedClipID = newProject.clips.first?.id
                self.showToast("Loaded new recording with \(newProject.zoomSegments.count) auto-zoom keyframes")
            }
        }

        recomputeCurrentFrame()
    }

    // MARK: - Frame Evaluation & Real-Time Compositing

    public func recomputeCurrentFrame() {
        let mapped = project.mapTimelineToSourceTime(playheadTime)
        let state = springSolver.evaluate(atSourceTime: mapped.sourceTime, in: project)
        self.currentFrameState = state

        let previewCanvasSize = project.aspectRatio.canvasSize(
            for: project.telemetry.sourceSize,
            baseHeight: 720
        )
        self.currentPreviewImage = compositor.renderCompositeFrame(
            project: project,
            frameState: state,
            canvasSize: previewCanvasSize,
            bundleURL: bundleURL,
            liveWebcamImage: captureCoordinator.liveWebcamCGImage
        )
    }

    // MARK: - Playback Transport (60fps)

    public func togglePlayback() {
        if isPlaying {
            pausePlayback()
        } else {
            startPlayback()
        }
    }

    public func startPlayback() {
        guard !isPlaying else { return }
        if playheadTime >= project.totalTimelineDuration - 0.05 {
            playheadTime = 0
        }
        isPlaying = true
        let dt = 1.0 / 60.0
        let timer = Timer(timeInterval: dt, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                let nextTime = self.playheadTime + dt
                if nextTime >= self.project.totalTimelineDuration {
                    self.playheadTime = 0.0
                    self.pausePlayback()
                } else {
                    self.playheadTime = nextTime
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.playbackTimer = timer
    }

    public func pausePlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    public func seek(to time: TimeInterval) {
        playheadTime = min(max(0.0, time), project.totalTimelineDuration)
    }

    // MARK: - Undo / Redo Management

    public func recordUndoSnapshot() {
        undoStack.append(project)
        if undoStack.count > 35 {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        project = previous
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        project = next
    }

    // MARK: - Timeline Editing Actions

    public func addZoomSegmentAtPlayhead() {
        recordUndoSnapshot()
        let mapped = project.mapTimelineToSourceTime(playheadTime)
        let start = max(0, mapped.sourceTime - 0.15)
        let end = min(project.telemetry.duration, start + 2.2)
        let newSeg = ZoomSegment(
            startTime: start,
            endTime: max(start + 0.4, end),
            zoomDepth: 2.2,
            mode: .followCursor,
            transitionPreset: .quick,
            isAutoGenerated: false
        )
        project.zoomSegments.append(newSeg)
        project.zoomSegments.sort { $0.startTime < $1.startTime }
        selectedZoomSegmentID = newSeg.id
        selectedInspectorTab = .cursorZoom
        showToast("Added Zoom Keyframe (\(String(format: "%.1fx", newSeg.zoomDepth)))")
    }

    public func deleteSelectedZoomSegment() {
        guard let id = selectedZoomSegmentID else { return }
        recordUndoSnapshot()
        project.zoomSegments.removeAll { $0.id == id }
        selectedZoomSegmentID = project.zoomSegments.first?.id
        showToast("Removed Zoom Keyframe")
    }

    public func regenerateAutoZooms(config: AutoZoomGenerator.Configuration = AutoZoomGenerator.Configuration()) {
        recordUndoSnapshot()
        let generated = AutoZoomGenerator.generateZoomSegments(from: project.telemetry, config: config)
        project.zoomSegments = generated
        selectedZoomSegmentID = generated.first?.id
        showToast("Auto-generated \(generated.count) Zoom segments from clicks & typing")
    }

    public func splitClipAtPlayhead() {
        guard !project.clips.isEmpty else { return }
        var accum: TimeInterval = 0
        for idx in project.clips.indices {
            let clip = project.clips[idx]
            let dur = clip.timelineDuration
            if playheadTime > accum + 0.25 && playheadTime < accum + dur - 0.25 {
                recordUndoSnapshot()
                let localTimelineOffset = playheadTime - accum
                let splitSourceTime = clip.sourceStartTime + localTimelineOffset * clip.speedMultiplier

                let firstHalf = ClipSegment(
                    label: "\(clip.label) A",
                    sourceStartTime: clip.sourceStartTime,
                    sourceEndTime: splitSourceTime,
                    speedMultiplier: clip.speedMultiplier,
                    isMuted: clip.isMuted
                )
                let secondHalf = ClipSegment(
                    label: "\(clip.label) B",
                    sourceStartTime: splitSourceTime,
                    sourceEndTime: clip.sourceEndTime,
                    speedMultiplier: clip.speedMultiplier,
                    isMuted: clip.isMuted
                )
                project.clips.replaceSubrange(idx...idx, with: [firstHalf, secondHalf])
                selectedClipID = secondHalf.id
                showToast("Split clip at \(String(format: "%.2fs", playheadTime))")
                return
            }
            accum += dur
        }
        showToast("Move playhead inside a clip to split")
    }

    public func deleteSelectedClip() {
        guard let clipID = selectedClipID, project.clips.count > 1 else {
            showToast("Cannot delete the only remaining clip")
            return
        }
        recordUndoSnapshot()
        project.clips.removeAll { $0.id == clipID }
        selectedClipID = project.clips.first?.id
        playheadTime = min(playheadTime, project.totalTimelineDuration)
        showToast("Ripple-deleted clip segment")
    }

    public func addSpeedRampAtPlayhead(multiplier: Double = 2.0) {
        recordUndoSnapshot()
        let mapped = project.mapTimelineToSourceTime(playheadTime)
        let start = max(0, mapped.sourceTime)
        let end = min(project.telemetry.duration, start + 2.0)
        let ramp = SpeedRampSegment(
            startTime: start,
            endTime: max(start + 0.4, end),
            speedMultiplier: multiplier,
            easeDuration: 0.25
        )
        project.speedRampSegments.append(ramp)
        project.speedRampSegments.sort { $0.startTime < $1.startTime }
        selectedSpeedRampID = ramp.id
        showToast("Added \(String(format: "%.1fx", multiplier)) Speed Ramp")
    }

    public func deleteSelectedSpeedRamp() {
        guard let id = selectedSpeedRampID else { return }
        recordUndoSnapshot()
        project.speedRampSegments.removeAll { $0.id == id }
        selectedSpeedRampID = project.speedRampSegments.first?.id
        showToast("Removed Speed Ramp")
    }

    public func generateAutoCaptions() {
        Task {
            let segments = await captionService.generateCaptions(for: project, bundleURL: bundleURL)
            recordUndoSnapshot()
            project.captionSegments = segments
            project.captionStyle.isEnabled = true
            selectedCaptionID = segments.first?.id
            showToast("Generated \(segments.count) Auto-Caption segments")
        }
    }

    public func saveProjectBundle() {
        do {
            let targetURL: URL
            if let existing = bundleURL {
                targetURL = existing
            } else {
                targetURL = try ProjectBundleManager.createNewBundleDirectory(title: project.title)
                self.bundleURL = targetURL
            }
            try ProjectBundleManager.save(project: project, to: targetURL)
            showToast("Saved project to \(targetURL.lastPathComponent)")
        } catch {
            showToast("Save failed: \(error.localizedDescription)")
        }
    }

    public func loadDemoProject() {
        recordUndoSnapshot()
        bundleURL = nil
        project = ProjectBundleManager.makeInteractiveDemoProject()
        playheadTime = 0
        selectedZoomSegmentID = project.zoomSegments.first?.id
        selectedClipID = project.clips.first?.id
        showToast("Loaded Interactive Demo Project")
    }

    public func showToast(_ message: String) {
        toastBannerMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if self.toastBannerMessage == message {
                self.toastBannerMessage = nil
            }
        }
    }
}
