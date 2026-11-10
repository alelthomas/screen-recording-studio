import Foundation
import AppKit
import CoreGraphics

@MainActor
public final class InputTelemetryMonitor: ObservableObject {
    @Published public private(set) var latestNormalizedCursor: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published public private(set) var latestKeystrokeLabel: String = ""
    @Published public private(set) var clickCount: Int = 0

    private var timer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    private var startTime: TimeInterval = 0
    private var pausedAccumulated: TimeInterval = 0
    private var pauseStartTime: TimeInterval?
    private var captureBounds: CGRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    private var cursorSamples: [CursorSample] = []
    private var clickEvents: [ClickEvent] = []
    private var scrollEvents: [ScrollEvent] = []
    private var keystrokeEvents: [KeystrokeEvent] = []

    public init() {}

    public func startMonitoring(captureBounds: CGRect) {
        stopMonitoring()
        self.captureBounds = captureBounds.width > 10 && captureBounds.height > 10
            ? captureBounds
            : (NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080))
        self.startTime = ProcessInfo.processInfo.systemUptime
        self.pausedAccumulated = 0
        self.pauseStartTime = nil
        self.cursorSamples.removeAll(keepingCapacity: true)
        self.clickEvents.removeAll(keepingCapacity: true)
        self.scrollEvents.removeAll(keepingCapacity: true)
        self.keystrokeEvents.removeAll(keepingCapacity: true)
        self.clickCount = 0
        self.latestKeystrokeLabel = ""

        // 120Hz cursor position sampler
        let sampleTimer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleCurrentCursor()
            }
        }
        RunLoop.main.add(sampleTimer, forMode: .common)
        self.timer = sampleTimer

        let mouseMask: NSEvent.EventTypeMask = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .scrollWheel
        ]

        self.globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseEvent(event)
            }
        }
        self.localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseMask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleMouseEvent(event)
            }
            return event
        }

        let keyMask: NSEvent.EventTypeMask = [.keyDown]
        self.globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: keyMask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyEvent(event)
            }
        }
        self.localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: keyMask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyEvent(event)
            }
            return event
        }
    }

    public func pauseMonitoring() {
        guard pauseStartTime == nil else { return }
        pauseStartTime = ProcessInfo.processInfo.systemUptime
    }

    public func resumeMonitoring() {
        guard let pausedAt = pauseStartTime else { return }
        pausedAccumulated += (ProcessInfo.processInfo.systemUptime - pausedAt)
        pauseStartTime = nil
    }

    @discardableResult
    public func stopMonitoring() -> RecordingTelemetry {
        timer?.invalidate()
        timer = nil
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }

        let totalDur = max(0.5, currentRecordingTime())
        return RecordingTelemetry(
            duration: totalDur,
            sourceSize: captureBounds.size,
            sampleRateHz: 120,
            cursorSamples: cursorSamples,
            clickEvents: clickEvents,
            scrollEvents: scrollEvents,
            keystrokeEvents: keystrokeEvents
        )
    }

    private func currentRecordingTime() -> TimeInterval {
        let now = pauseStartTime ?? ProcessInfo.processInfo.systemUptime
        return max(0.0, now - startTime - pausedAccumulated)
    }

    private func normalizedCursorPoint() -> CGPoint {
        let globalLoc = NSEvent.mouseLocation
        let screenHeight = NSScreen.screens.first?.frame.height ?? 1080
        // Convert AppKit bottom-left screen coordinate to top-left coordinate
        let topLeftGlobal = CGPoint(x: globalLoc.x, y: screenHeight - globalLoc.y)
        let normX = (topLeftGlobal.x - captureBounds.minX) / max(1.0, captureBounds.width)
        let normY = (topLeftGlobal.y - captureBounds.minY) / max(1.0, captureBounds.height)
        return CGPoint(
            x: min(1.0, max(0.0, normX)),
            y: min(1.0, max(0.0, normY))
        )
    }

    private func sampleCurrentCursor() {
        guard pauseStartTime == nil else { return }
        let t = currentRecordingTime()
        let pos = normalizedCursorPoint()
        latestNormalizedCursor = pos
        let style = detectCurrentCursorStyle()
        cursorSamples.append(CursorSample(timestamp: t, normalizedPos: pos, cursorType: style))
    }

    private func detectCurrentCursorStyle() -> CursorStyle {
        let current = NSCursor.currentSystem ?? NSCursor.current
        if current == NSCursor.pointingHand { return .pointingHand }
        if current == NSCursor.iBeam { return .iBeam }
        if current == NSCursor.crosshair { return .crosshair }
        if current == NSCursor.openHand { return .openHand }
        if current == NSCursor.closedHand { return .closedHand }
        if current == NSCursor.resizeLeftRight { return .resizeLeftRight }
        if current == NSCursor.resizeUpDown { return .resizeUpDown }
        return .arrow
    }

    private func handleMouseEvent(_ event: NSEvent) {
        guard pauseStartTime == nil else { return }
        let t = currentRecordingTime()
        let pos = normalizedCursorPoint()

        switch event.type {
        case .leftMouseDown:
            clickEvents.append(ClickEvent(timestamp: t, button: .left, phase: .down, normalizedPos: pos))
            clickCount += 1
        case .leftMouseUp:
            clickEvents.append(ClickEvent(timestamp: t, button: .left, phase: .up, normalizedPos: pos))
        case .leftMouseDragged:
            clickEvents.append(ClickEvent(timestamp: t, button: .left, phase: .drag, normalizedPos: pos))
        case .rightMouseDown:
            clickEvents.append(ClickEvent(timestamp: t, button: .right, phase: .down, normalizedPos: pos))
            clickCount += 1
        case .rightMouseUp:
            clickEvents.append(ClickEvent(timestamp: t, button: .right, phase: .up, normalizedPos: pos))
        case .scrollWheel:
            scrollEvents.append(
                ScrollEvent(
                    timestamp: t,
                    deltaX: Double(event.scrollingDeltaX),
                    deltaY: Double(event.scrollingDeltaY),
                    normalizedPos: pos
                )
            )
        default:
            break
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard pauseStartTime == nil else { return }
        let t = currentRecordingTime()
        let pos = normalizedCursorPoint()
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        var mods: [ModifierKey] = []
        if flags.contains(.control) { mods.append(.control) }
        if flags.contains(.option) { mods.append(.option) }
        if flags.contains(.shift) { mods.append(.shift) }
        if flags.contains(.command) { mods.append(.command) }

        let chars = event.charactersIgnoringModifiers ?? ""
        let keyLabel = Self.humanReadableKeyName(keyCode: event.keyCode, characters: chars)
        let isShortcut = flags.contains(.command) || flags.contains(.control) || flags.contains(.option) || Self.isSpecialFunctionKey(event.keyCode)

        let display = (mods.map { $0.rawValue } + [keyLabel]).joined(separator: " ")
        latestKeystrokeLabel = display

        keystrokeEvents.append(
            KeystrokeEvent(
                timestamp: t,
                characters: chars,
                displayLabel: display,
                keyCode: event.keyCode,
                modifiers: mods,
                isShortcut: isShortcut,
                cursorNormalizedPos: pos
            )
        )
    }

    private static func isSpecialFunctionKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 36, 48, 49, 51, 53, 123, 124, 125, 126:
            return true
        default:
            return false
        }
    }

    private static func humanReadableKeyName(keyCode: UInt16, characters: String) -> String {
        switch keyCode {
        case 36: return "⏎ Return"
        case 48: return "⇥ Tab"
        case 49: return "Space"
        case 51: return "⌫ Delete"
        case 53: return "⎋ Esc"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let upper = characters.uppercased()
            return upper.isEmpty ? "Key \(keyCode)" : upper
        }
    }
}
