import Foundation
import CoreGraphics

// MARK: - Cursor Style

public enum CursorStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case arrow = "arrow"
    case pointingHand = "pointingHand"
    case iBeam = "iBeam"
    case crosshair = "crosshair"
    case openHand = "openHand"
    case closedHand = "closedHand"
    case resizeLeftRight = "resizeLeftRight"
    case resizeUpDown = "resizeUpDown"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .arrow: return "macOS Arrow"
        case .pointingHand: return "Pointing Hand"
        case .iBeam: return "Text I-Beam"
        case .crosshair: return "Crosshair"
        case .openHand: return "Open Hand"
        case .closedHand: return "Closed Hand"
        case .resizeLeftRight: return "Resize Horizontal"
        case .resizeUpDown: return "Resize Vertical"
        }
    }
}

// MARK: - Mouse Events

public enum MouseButton: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case middle
}

public enum MousePhase: String, Codable, CaseIterable, Sendable {
    case down
    case up
    case drag
}

public struct CursorSample: Codable, Equatable, Sendable {
    public var timestamp: TimeInterval
    /// Normalized coordinates in [0.0, 1.0] where (0, 0) is top-left of captured source.
    public var normalizedPos: CGPoint
    public var cursorType: CursorStyle

    public init(timestamp: TimeInterval, normalizedPos: CGPoint, cursorType: CursorStyle = .arrow) {
        self.timestamp = timestamp
        self.normalizedPos = normalizedPos
        self.cursorType = cursorType
    }
}

public struct ClickEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: TimeInterval
    public var button: MouseButton
    public var phase: MousePhase
    public var normalizedPos: CGPoint

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        button: MouseButton = .left,
        phase: MousePhase = .down,
        normalizedPos: CGPoint
    ) {
        self.id = id
        self.timestamp = timestamp
        self.button = button
        self.phase = phase
        self.normalizedPos = normalizedPos
    }
}

public struct ScrollEvent: Codable, Equatable, Sendable {
    public var timestamp: TimeInterval
    public var deltaX: Double
    public var deltaY: Double
    public var normalizedPos: CGPoint

    public init(timestamp: TimeInterval, deltaX: Double, deltaY: Double, normalizedPos: CGPoint) {
        self.timestamp = timestamp
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.normalizedPos = normalizedPos
    }
}

// MARK: - Keyboard Telemetry

public enum ModifierKey: String, Codable, CaseIterable, Hashable, Sendable {
    case command = "⌘"
    case shift = "⇧"
    case option = "⌥"
    case control = "⌃"
    case function = "fn"
}

public struct KeystrokeEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var timestamp: TimeInterval
    public var characters: String
    public var displayLabel: String
    public var keyCode: UInt16
    public var modifiers: [ModifierKey]
    public var isShortcut: Bool
    /// Cursor location at the moment the key was pressed (used for typing-burst zoom target).
    public var cursorNormalizedPos: CGPoint

    public init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        characters: String,
        displayLabel: String,
        keyCode: UInt16,
        modifiers: [ModifierKey],
        isShortcut: Bool,
        cursorNormalizedPos: CGPoint = CGPoint(x: 0.5, y: 0.5)
    ) {
        self.id = id
        self.timestamp = timestamp
        self.characters = characters
        self.displayLabel = displayLabel
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isShortcut = isShortcut
        self.cursorNormalizedPos = cursorNormalizedPos
    }
}

// MARK: - Complete Session Telemetry

public struct RecordingTelemetry: Codable, Equatable, Sendable {
    public var duration: TimeInterval
    public var sourceSize: CGSize
    public var sampleRateHz: Int
    public var cursorSamples: [CursorSample]
    public var clickEvents: [ClickEvent]
    public var scrollEvents: [ScrollEvent]
    public var keystrokeEvents: [KeystrokeEvent]

    public init(
        duration: TimeInterval = 12.0,
        sourceSize: CGSize = CGSize(width: 1920, height: 1080),
        sampleRateHz: Int = 120,
        cursorSamples: [CursorSample] = [],
        clickEvents: [ClickEvent] = [],
        scrollEvents: [ScrollEvent] = [],
        keystrokeEvents: [KeystrokeEvent] = []
    ) {
        self.duration = duration
        self.sourceSize = sourceSize
        self.sampleRateHz = sampleRateHz
        self.cursorSamples = cursorSamples
        self.clickEvents = clickEvents
        self.scrollEvents = scrollEvents
        self.keystrokeEvents = keystrokeEvents
    }
}
