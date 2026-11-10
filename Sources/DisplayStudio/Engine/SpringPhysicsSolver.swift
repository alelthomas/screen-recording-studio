import Foundation
import CoreGraphics

// MARK: - Evaluated Frame State

public struct ActiveClickRipple: Equatable, Sendable {
    public var id: UUID
    public var normalizedPos: CGPoint
    /// Progress in [0.0 ... 1.0].
    public var progress: Double
    public var button: MouseButton

    public init(id: UUID, normalizedPos: CGPoint, progress: Double, button: MouseButton) {
        self.id = id
        self.normalizedPos = normalizedPos
        self.progress = progress
        self.button = button
    }
}

public struct EvaluatedFrameState: Equatable, Sendable {
    public var sourceTime: TimeInterval
    public var smoothedCursorPos: CGPoint
    public var rawCursorPos: CGPoint
    public var cursorVelocity: CGVector
    public var cursorStyle: CursorStyle
    public var cursorOpacity: Double
    public var cursorClickScale: Double
    public var activeRipples: [ActiveClickRipple]

    public var cameraCenter: CGPoint
    public var cameraZoom: Double
    public var cameraVelocity: CGVector
    public var activeZoomSegmentID: UUID?

    public var activeKeystrokes: [KeystrokeEvent]
    public var activeCaption: CaptionSegment?
    public var webcamDuckScale: Double

    public init(
        sourceTime: TimeInterval = 0,
        smoothedCursorPos: CGPoint = CGPoint(x: 0.5, y: 0.5),
        rawCursorPos: CGPoint = CGPoint(x: 0.5, y: 0.5),
        cursorVelocity: CGVector = .zero,
        cursorStyle: CursorStyle = .arrow,
        cursorOpacity: Double = 1.0,
        cursorClickScale: Double = 1.0,
        activeRipples: [ActiveClickRipple] = [],
        cameraCenter: CGPoint = CGPoint(x: 0.5, y: 0.5),
        cameraZoom: Double = 1.0,
        cameraVelocity: CGVector = .zero,
        activeZoomSegmentID: UUID? = nil,
        activeKeystrokes: [KeystrokeEvent] = [],
        activeCaption: CaptionSegment? = nil,
        webcamDuckScale: Double = 1.0
    ) {
        self.sourceTime = sourceTime
        self.smoothedCursorPos = smoothedCursorPos
        self.rawCursorPos = rawCursorPos
        self.cursorVelocity = cursorVelocity
        self.cursorStyle = cursorStyle
        self.cursorOpacity = cursorOpacity
        self.cursorClickScale = cursorClickScale
        self.activeRipples = activeRipples
        self.cameraCenter = cameraCenter
        self.cameraZoom = cameraZoom
        self.cameraVelocity = cameraVelocity
        self.activeZoomSegmentID = activeZoomSegmentID
        self.activeKeystrokes = activeKeystrokes
        self.activeCaption = activeCaption
        self.webcamDuckScale = webcamDuckScale
    }
}

// MARK: - Second-Order Spring Physics Solver

public final class SpringPhysicsSolver {
    private struct BakedStep {
        var time: TimeInterval
        var cursorPos: CGPoint
        var rawPos: CGPoint
        var cursorVel: CGVector
        var cursorStyle: CursorStyle
        var cursorOpacity: Double
        var clickScale: Double
        var cameraCenter: CGPoint
        var cameraZoom: Double
        var cameraVel: CGVector
        var activeZoomID: UUID?
    }

    private var bakedSteps: [BakedStep] = []
    private let stepHz: Double = 120.0
    private var lastBakedSignature: Int = 0

    public init() {}

    /// Re-bakes the 120Hz spring trajectory whenever cursor settings, zoom segments, or telemetry change.
    public func ensureBaked(for project: StudioProject) {
        var hasher = Hasher()
        hasher.combine(project.cursorSettings)
        hasher.combine(project.zoomSegments)
        hasher.combine(project.telemetry.duration)
        hasher.combine(project.telemetry.cursorSamples.count)
        hasher.combine(project.telemetry.clickEvents.count)
        let signature = hasher.finalize()

        guard signature != lastBakedSignature || bakedSteps.isEmpty else { return }
        lastBakedSignature = signature
        bakeTrajectory(for: project)
    }

    private func bakeTrajectory(for project: StudioProject) {
        let duration = max(0.5, project.telemetry.duration)
        let totalSteps = max(2, Int(ceil(duration * stepHz)))
        let dt = 1.0 / stepHz
        let subSteps = 2
        let subDt = dt / Double(subSteps)

        let cursorParams: (stiffness: Double, damping: Double, mass: Double) = {
            if project.cursorSettings.springPreset == .custom {
                return (
                    max(20, project.cursorSettings.stiffness),
                    max(4, project.cursorSettings.damping),
                    max(0.2, project.cursorSettings.mass)
                )
            }
            return project.cursorSettings.springPreset.parameters
        }()

        let initialRaw = rawSample(at: 0, in: project.telemetry)
        var curX = Double(initialRaw.normalizedPos.x)
        var curY = Double(initialRaw.normalizedPos.y)
        var velX = 0.0
        var velY = 0.0

        var camX = 0.5
        var camY = 0.5
        var camVelX = 0.0
        var camVelY = 0.0
        var camZoom = 1.0
        var camZoomVel = 0.0

        var clickScale = 1.0
        var clickScaleVel = 0.0

        var lastMovementTime: TimeInterval = 0.0
        var opacity = 1.0

        var steps: [BakedStep] = []
        steps.reserveCapacity(totalSteps + 1)

        let sortedZooms = project.zoomSegments.sorted { $0.startTime < $1.startTime }

        for i in 0...totalSteps {
            let t = Double(i) * dt
            let raw = rawSample(at: t, in: project.telemetry)
            let targetX = Double(raw.normalizedPos.x)
            let targetY = Double(raw.normalizedPos.y)

            // Integrate cursor spring
            for _ in 0..<subSteps {
                let ax = (-cursorParams.stiffness * (curX - targetX) - cursorParams.damping * velX) / cursorParams.mass
                let ay = (-cursorParams.stiffness * (curY - targetY) - cursorParams.damping * velY) / cursorParams.mass
                velX += ax * subDt
                velY += ay * subDt
                curX += velX * subDt
                curY += velY * subDt
            }

            let speed = hypot(velX, velY)
            if speed > 0.015 {
                lastMovementTime = t
            }

            if project.cursorSettings.autoHideIdle {
                let idleDuration = t - lastMovementTime
                if idleDuration > project.cursorSettings.idleTimeoutSeconds {
                    opacity = max(0.0, opacity - dt * 3.5)
                } else {
                    opacity = min(1.0, opacity + dt * 6.0)
                }
            } else {
                opacity = 1.0
            }

            // Click scale bounce spring
            let isMouseDown = isButtonPressed(at: t, clicks: project.telemetry.clickEvents)
            let targetClickScale = isMouseDown ? project.cursorSettings.clickBounceScale : 1.0
            let clickAcc = -420.0 * (clickScale - targetClickScale) - 28.0 * clickScaleVel
            clickScaleVel += clickAcc * dt
            clickScale += clickScaleVel * dt

            // Active zoom segment lookup
            let activeZoom = sortedZooms.first { t >= $0.startTime && t <= $0.endTime }
            let targetZoom = activeZoom?.zoomDepth ?? 1.0
            let zoomSpring = activeZoom?.transitionPreset.springParameters ?? (stiffness: 155.0, damping: 24.0)

            var rawTargetCamX = 0.5
            var rawTargetCamY = 0.5
            if let seg = activeZoom {
                switch seg.mode {
                case .followCursor:
                    rawTargetCamX = curX
                    rawTargetCamY = curY
                case .fixedPoint(let pt):
                    rawTargetCamX = Double(pt.x)
                    rawTargetCamY = Double(pt.y)
                }
            }

            // Clamp camera center so zoomed viewport stays within [0, 1] bounds
            let halfSpan = 0.5 / max(1.0, targetZoom)
            let clampedTargetCamX = min(max(rawTargetCamX, halfSpan), 1.0 - halfSpan)
            let clampedTargetCamY = min(max(rawTargetCamY, halfSpan), 1.0 - halfSpan)

            for _ in 0..<subSteps {
                let zAcc = -zoomSpring.stiffness * (camZoom - targetZoom) - zoomSpring.damping * camZoomVel
                camZoomVel += zAcc * subDt
                camZoom = max(1.0, camZoom + camZoomVel * subDt)

                let cxAcc = -zoomSpring.stiffness * (camX - clampedTargetCamX) - zoomSpring.damping * camVelX
                let cyAcc = -zoomSpring.stiffness * (camY - clampedTargetCamY) - zoomSpring.damping * camVelY
                camVelX += cxAcc * subDt
                camVelY += cyAcc * subDt
                camX += camVelX * subDt
                camY += camVelY * subDt
            }

            // Clamp final integrated camera center for current instantaneous zoom
            let instHalfSpan = 0.5 / max(1.0, camZoom)
            let finalCamX = min(max(camX, instHalfSpan), 1.0 - instHalfSpan)
            let finalCamY = min(max(camY, instHalfSpan), 1.0 - instHalfSpan)

            let style = project.cursorSettings.styleOverride ?? raw.cursorType

            steps.append(
                BakedStep(
                    time: t,
                    cursorPos: CGPoint(x: min(1, max(0, curX)), y: min(1, max(0, curY))),
                    rawPos: raw.normalizedPos,
                    cursorVel: CGVector(dx: velX, dy: velY),
                    cursorStyle: style,
                    cursorOpacity: project.cursorSettings.showCursor ? opacity : 0.0,
                    clickScale: clickScale,
                    cameraCenter: CGPoint(x: finalCamX, y: finalCamY),
                    cameraZoom: camZoom,
                    cameraVel: CGVector(dx: camVelX, dy: camVelY),
                    activeZoomID: activeZoom?.id
                )
            )
        }

        self.bakedSteps = steps
    }

    public func evaluate(atSourceTime sourceTime: TimeInterval, in project: StudioProject) -> EvaluatedFrameState {
        ensureBaked(for: project)
        guard !bakedSteps.isEmpty else {
            return EvaluatedFrameState(sourceTime: sourceTime)
        }

        let clampedTime = min(max(0.0, sourceTime), project.telemetry.duration)
        let exactIndex = clampedTime * stepHz
        let lowerIdx = min(bakedSteps.count - 1, max(0, Int(floor(exactIndex))))
        let upperIdx = min(bakedSteps.count - 1, lowerIdx + 1)
        let frac = exactIndex - Double(lowerIdx)

        let a = bakedSteps[lowerIdx]
        let b = bakedSteps[upperIdx]

        let curPos = CGPoint(
            x: a.cursorPos.x + (b.cursorPos.x - a.cursorPos.x) * frac,
            y: a.cursorPos.y + (b.cursorPos.y - a.cursorPos.y) * frac
        )
        let camCenter = CGPoint(
            x: a.cameraCenter.x + (b.cameraCenter.x - a.cameraCenter.x) * frac,
            y: a.cameraCenter.y + (b.cameraCenter.y - a.cameraCenter.y) * frac
        )
        let camZoom = a.cameraZoom + (b.cameraZoom - a.cameraZoom) * frac

        // Active click ripples
        var ripples: [ActiveClickRipple] = []
        if project.cursorSettings.showClickRipple {
            let rippleDur = max(0.15, project.cursorSettings.rippleDuration)
            for click in project.telemetry.clickEvents where click.phase == .down {
                let elapsed = clampedTime - click.timestamp
                if elapsed >= 0 && elapsed <= rippleDur {
                    ripples.append(
                        ActiveClickRipple(
                            id: click.id,
                            normalizedPos: click.normalizedPos,
                            progress: elapsed / rippleDur,
                            button: click.button
                        )
                    )
                }
            }
        }

        // Active keystrokes
        var activeKeys: [KeystrokeEvent] = []
        if project.keystrokeSettings.isEnabled {
            let hold = max(0.4, project.keystrokeSettings.holdDurationSeconds)
            for key in project.telemetry.keystrokeEvents {
                if project.keystrokeSettings.shortcutsOnly && !key.isShortcut {
                    continue
                }
                let elapsed = clampedTime - key.timestamp
                if elapsed >= 0 && elapsed <= hold {
                    activeKeys.append(key)
                }
            }
        }

        // Active caption
        let activeCaption: CaptionSegment? = project.captionStyle.isEnabled
            ? project.captionSegments.first(where: { clampedTime >= $0.startTime && clampedTime <= $0.endTime })
            : nil

        // Webcam auto-ducking if camera zooms into the webcam corner
        var webcamDuck = 1.0
        if project.webcamSettings.isEnabled && project.webcamSettings.autoDuckOnZoom && camZoom > 1.25 {
            let webcamCenter: CGPoint = {
                switch project.webcamSettings.corner {
                case .bottomRight: return CGPoint(x: 0.85, y: 0.82)
                case .bottomLeft: return CGPoint(x: 0.15, y: 0.82)
                case .topRight: return CGPoint(x: 0.85, y: 0.18)
                case .topLeft: return CGPoint(x: 0.15, y: 0.18)
                case .custom: return project.webcamSettings.customNormalizedCenter
                }
            }()
            let dist = hypot(camCenter.x - webcamCenter.x, camCenter.y - webcamCenter.y)
            if dist < 0.35 {
                let proximity = 1.0 - (dist / 0.35)
                webcamDuck = max(0.52, 1.0 - 0.45 * proximity)
            }
        }

        return EvaluatedFrameState(
            sourceTime: clampedTime,
            smoothedCursorPos: curPos,
            rawCursorPos: a.rawPos,
            cursorVelocity: a.cursorVel,
            cursorStyle: a.cursorStyle,
            cursorOpacity: a.cursorOpacity,
            cursorClickScale: a.clickScale,
            activeRipples: ripples,
            cameraCenter: camCenter,
            cameraZoom: camZoom,
            cameraVelocity: a.cameraVel,
            activeZoomSegmentID: a.activeZoomID,
            activeKeystrokes: activeKeys,
            activeCaption: activeCaption,
            webcamDuckScale: webcamDuck
        )
    }

    private func rawSample(at time: TimeInterval, in telemetry: RecordingTelemetry) -> CursorSample {
        let samples = telemetry.cursorSamples
        guard !samples.isEmpty else {
            return CursorSample(timestamp: time, normalizedPos: CGPoint(x: 0.5, y: 0.5), cursorType: .arrow)
        }
        if time <= samples.first!.timestamp { return samples.first! }
        if time >= samples.last!.timestamp { return samples.last! }

        // Binary search
        var low = 0
        var high = samples.count - 1
        while low + 1 < high {
            let mid = (low + high) / 2
            if samples[mid].timestamp <= time {
                low = mid
            } else {
                high = mid
            }
        }
        let s0 = samples[low]
        let s1 = samples[high]
        let span = max(0.0001, s1.timestamp - s0.timestamp)
        let frac = min(1.0, max(0.0, (time - s0.timestamp) / span))
        let pos = CGPoint(
            x: s0.normalizedPos.x + (s1.normalizedPos.x - s0.normalizedPos.x) * frac,
            y: s0.normalizedPos.y + (s1.normalizedPos.y - s0.normalizedPos.y) * frac
        )
        return CursorSample(timestamp: time, normalizedPos: pos, cursorType: frac > 0.5 ? s1.cursorType : s0.cursorType)
    }

    private func isButtonPressed(at time: TimeInterval, clicks: [ClickEvent]) -> Bool {
        var pressed = false
        for event in clicks where event.timestamp <= time {
            if event.phase == .down || event.phase == .drag {
                pressed = true
            } else if event.phase == .up {
                pressed = false
            }
        }
        for event in clicks where event.phase == .down {
            if abs(time - event.timestamp) < 0.08 {
                return true
            }
        }
        return pressed
    }
}
