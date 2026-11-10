import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Codable Color Helper

public struct CodableColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    public var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public init(nsColor: NSColor) {
        let converted = nsColor.usingColorSpace(.sRGB) ?? nsColor
        self.red = Double(converted.redComponent)
        self.green = Double(converted.greenComponent)
        self.blue = Double(converted.blueComponent)
        self.alpha = Double(converted.alphaComponent)
    }
}

// MARK: - Aspect Ratio Presets

public enum AspectRatioPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto = "Auto (Source)"
    case widescreen16x9 = "16:9 Wide"
    case vertical9x16 = "9:16 Vertical"
    case square1x1 = "1:1 Square"
    case classic4x3 = "4:3 Classic"
    case mac16x10 = "16:10 macOS"

    public var id: String { rawValue }

    public func canvasSize(for sourceSize: CGSize, baseHeight: CGFloat = 1080) -> CGSize {
        switch self {
        case .auto:
            let ratio = max(0.25, sourceSize.width / max(1, sourceSize.height))
            return CGSize(width: round(baseHeight * ratio), height: baseHeight)
        case .widescreen16x9:
            return CGSize(width: round(baseHeight * 16.0 / 9.0), height: baseHeight)
        case .vertical9x16:
            return CGSize(width: round(baseHeight * 9.0 / 16.0), height: baseHeight)
        case .square1x1:
            return CGSize(width: baseHeight, height: baseHeight)
        case .classic4x3:
            return CGSize(width: round(baseHeight * 4.0 / 3.0), height: baseHeight)
        case .mac16x10:
            return CGSize(width: round(baseHeight * 16.0 / 10.0), height: baseHeight)
        }
    }
}

// MARK: - Backgrounds & Wallpapers

public enum WallpaperPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case sequoiaSunrise = "Sequoia Sunrise"
    case sonomaHorizon = "Sonoma Horizon"
    case venturaEmber = "Ventura Ember"
    case midnightNebula = "Midnight Nebula"
    case cyberAurora = "Cyber Aurora"
    case minimalSlate = "Minimal Slate"
    case oceanGlass = "Ocean Glass"
    case sunsetDunes = "Sunset Dunes"

    public var id: String { rawValue }

    public var colors: [CodableColor] {
        switch self {
        case .sequoiaSunrise:
            return [
                CodableColor(red: 0.14, green: 0.10, blue: 0.36),
                CodableColor(red: 0.48, green: 0.19, blue: 0.54),
                CodableColor(red: 0.95, green: 0.48, blue: 0.34),
                CodableColor(red: 0.99, green: 0.78, blue: 0.45)
            ]
        case .sonomaHorizon:
            return [
                CodableColor(red: 0.05, green: 0.20, blue: 0.42),
                CodableColor(red: 0.12, green: 0.48, blue: 0.68),
                CodableColor(red: 0.35, green: 0.78, blue: 0.75),
                CodableColor(red: 0.92, green: 0.65, blue: 0.48)
            ]
        case .venturaEmber:
            return [
                CodableColor(red: 0.16, green: 0.05, blue: 0.12),
                CodableColor(red: 0.68, green: 0.15, blue: 0.24),
                CodableColor(red: 0.95, green: 0.45, blue: 0.18),
                CodableColor(red: 0.99, green: 0.76, blue: 0.32)
            ]
        case .midnightNebula:
            return [
                CodableColor(red: 0.04, green: 0.05, blue: 0.14),
                CodableColor(red: 0.16, green: 0.10, blue: 0.38),
                CodableColor(red: 0.36, green: 0.18, blue: 0.64),
                CodableColor(red: 0.12, green: 0.52, blue: 0.82)
            ]
        case .cyberAurora:
            return [
                CodableColor(red: 0.03, green: 0.12, blue: 0.18),
                CodableColor(red: 0.06, green: 0.45, blue: 0.52),
                CodableColor(red: 0.22, green: 0.86, blue: 0.64),
                CodableColor(red: 0.45, green: 0.28, blue: 0.92)
            ]
        case .minimalSlate:
            return [
                CodableColor(red: 0.10, green: 0.11, blue: 0.14),
                CodableColor(red: 0.17, green: 0.19, blue: 0.24),
                CodableColor(red: 0.24, green: 0.27, blue: 0.33),
                CodableColor(red: 0.13, green: 0.15, blue: 0.19)
            ]
        case .oceanGlass:
            return [
                CodableColor(red: 0.02, green: 0.18, blue: 0.34),
                CodableColor(red: 0.05, green: 0.42, blue: 0.68),
                CodableColor(red: 0.18, green: 0.72, blue: 0.88),
                CodableColor(red: 0.62, green: 0.92, blue: 0.96)
            ]
        case .sunsetDunes:
            return [
                CodableColor(red: 0.22, green: 0.09, blue: 0.28),
                CodableColor(red: 0.62, green: 0.21, blue: 0.42),
                CodableColor(red: 0.91, green: 0.44, blue: 0.38),
                CodableColor(red: 0.98, green: 0.75, blue: 0.55)
            ]
        }
    }
}

public enum BackgroundMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case wallpaper = "Wallpaper"
    case gradient = "Gradient"
    case mesh = "Mesh"
    case solid = "Solid"
    case customImage = "Image"

    public var id: String { rawValue }
}

public struct BackgroundConfig: Codable, Equatable, Sendable {
    public var mode: BackgroundMode
    public var wallpaperPreset: WallpaperPreset
    public var gradientStart: CodableColor
    public var gradientEnd: CodableColor
    public var gradientAccent: CodableColor
    public var gradientAngleDegrees: Double
    public var solidColor: CodableColor
    public var customImagePath: String?
    public var backdropBlurRadius: Double
    public var brightness: Double
    public var vignetteIntensity: Double

    public init(
        mode: BackgroundMode = .wallpaper,
        wallpaperPreset: WallpaperPreset = .sequoiaSunrise,
        gradientStart: CodableColor = CodableColor(red: 0.24, green: 0.14, blue: 0.65),
        gradientEnd: CodableColor = CodableColor(red: 0.92, green: 0.38, blue: 0.54),
        gradientAccent: CodableColor = CodableColor(red: 0.18, green: 0.76, blue: 0.88),
        gradientAngleDegrees: Double = 135,
        solidColor: CodableColor = CodableColor(red: 0.11, green: 0.12, blue: 0.16),
        customImagePath: String? = nil,
        backdropBlurRadius: Double = 18.0,
        brightness: Double = 0.0,
        vignetteIntensity: Double = 0.22
    ) {
        self.mode = mode
        self.wallpaperPreset = wallpaperPreset
        self.gradientStart = gradientStart
        self.gradientEnd = gradientEnd
        self.gradientAccent = gradientAccent
        self.gradientAngleDegrees = gradientAngleDegrees
        self.solidColor = solidColor
        self.customImagePath = customImagePath
        self.backdropBlurRadius = backdropBlurRadius
        self.brightness = brightness
        self.vignetteIntensity = vignetteIntensity
    }
}

// MARK: - Frame Styling

public struct FrameStyling: Codable, Equatable, Sendable {
    /// Inset padding around the screen recording as a fraction of canvas size [0.0 ... 0.35].
    public var paddingRatio: Double
    /// Corner radius in canvas pixels [0 ... 64].
    public var cornerRadius: Double
    /// Drop shadow opacity [0.0 ... 1.0].
    public var shadowOpacity: Double
    /// Drop shadow blur radius [0 ... 80].
    public var shadowRadius: Double
    /// Drop shadow vertical offset [0 ... 40].
    public var shadowOffsetY: Double
    /// Subtle glass inner border width [0 ... 4].
    public var insetBorderWidth: Double
    public var insetBorderOpacity: Double

    public init(
        paddingRatio: Double = 0.09,
        cornerRadius: Double = 20.0,
        shadowOpacity: Double = 0.55,
        shadowRadius: Double = 38.0,
        shadowOffsetY: Double = 18.0,
        insetBorderWidth: Double = 1.5,
        insetBorderOpacity: Double = 0.28
    ) {
        self.paddingRatio = paddingRatio
        self.cornerRadius = cornerRadius
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowOffsetY = shadowOffsetY
        self.insetBorderWidth = insetBorderWidth
        self.insetBorderOpacity = insetBorderOpacity
    }
}

// MARK: - Spring Physics & Cursor Settings

public enum SpringPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case instant = "Instant"
    case natural = "Natural"
    case smooth = "Smooth"
    case cinematic = "Cinematic"
    case custom = "Custom"

    public var id: String { rawValue }

    public var parameters: (stiffness: Double, damping: Double, mass: Double) {
        switch self {
        case .instant:
            return (stiffness: 750.0, damping: 55.0, mass: 1.0)
        case .natural:
            return (stiffness: 320.0, damping: 34.0, mass: 1.0)
        case .smooth:
            return (stiffness: 180.0, damping: 26.0, mass: 1.0)
        case .cinematic:
            return (stiffness: 95.0, damping: 19.0, mass: 1.1)
        case .custom:
            return (stiffness: 180.0, damping: 26.0, mass: 1.0)
        }
    }
}

public struct CursorSettings: Codable, Equatable, Hashable, Sendable {
    public var showCursor: Bool
    /// Cursor scale multiplier [0.75 ... 3.5].
    public var scale: Double
    public var styleOverride: CursorStyle?
    public var springPreset: SpringPreset
    public var stiffness: Double
    public var damping: Double
    public var mass: Double
    public var autoHideIdle: Bool
    public var idleTimeoutSeconds: Double
    /// Scale multiplier during mouse down [0.65 ... 1.0].
    public var clickBounceScale: Double
    public var showClickRipple: Bool
    public var rippleColor: CodableColor
    public var rippleDuration: Double
    /// Directional & radial motion blur intensity [0.0 ... 1.0].
    public var motionBlurIntensity: Double
    /// Simulated camera shutter angle in degrees [0 ... 360].
    public var shutterAngleDegrees: Double

    public init(
        showCursor: Bool = true,
        scale: Double = 1.65,
        styleOverride: CursorStyle? = nil,
        springPreset: SpringPreset = .smooth,
        stiffness: Double = 180.0,
        damping: Double = 26.0,
        mass: Double = 1.0,
        autoHideIdle: Bool = true,
        idleTimeoutSeconds: Double = 2.5,
        clickBounceScale: Double = 0.82,
        showClickRipple: Bool = true,
        rippleColor: CodableColor = CodableColor(red: 0.38, green: 0.62, blue: 1.0, alpha: 0.78),
        rippleDuration: Double = 0.48,
        motionBlurIntensity: Double = 0.65,
        shutterAngleDegrees: Double = 180.0
    ) {
        self.showCursor = showCursor
        self.scale = scale
        self.styleOverride = styleOverride
        self.springPreset = springPreset
        self.stiffness = stiffness
        self.damping = damping
        self.mass = mass
        self.autoHideIdle = autoHideIdle
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.clickBounceScale = clickBounceScale
        self.showClickRipple = showClickRipple
        self.rippleColor = rippleColor
        self.rippleDuration = rippleDuration
        self.motionBlurIntensity = motionBlurIntensity
        self.shutterAngleDegrees = shutterAngleDegrees
    }
}

// MARK: - Zoom Keyframes & Transitions

public enum ZoomMode: Codable, Equatable, Hashable, Sendable {
    case followCursor
    case fixedPoint(CGPoint)

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .followCursor:
            hasher.combine(0)
        case .fixedPoint(let pt):
            hasher.combine(1)
            hasher.combine(Double(pt.x))
            hasher.combine(Double(pt.y))
        }
    }

    public var isFollowCursor: Bool {
        if case .followCursor = self { return true }
        return false
    }

    public var fixedCoordinate: CGPoint {
        if case .fixedPoint(let pt) = self { return pt }
        return CGPoint(x: 0.5, y: 0.5)
    }
}

public enum ZoomTransitionPreset: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case mellow = "Mellow"
    case quick = "Quick"
    case snappy = "Snappy"
    case bouncy = "Bouncy"

    public var id: String { rawValue }

    public var springParameters: (stiffness: Double, damping: Double) {
        switch self {
        case .mellow: return (stiffness: 90.0, damping: 20.0)
        case .quick: return (stiffness: 175.0, damping: 26.0)
        case .snappy: return (stiffness: 290.0, damping: 32.0)
        case .bouncy: return (stiffness: 220.0, damping: 18.0)
        }
    }
}

public struct ZoomSegment: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    /// Zoom magnification factor [1.15 ... 4.0].
    public var zoomDepth: Double
    public var mode: ZoomMode
    public var transitionPreset: ZoomTransitionPreset
    public var isAutoGenerated: Bool

    public var duration: TimeInterval {
        max(0.1, endTime - startTime)
    }

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        zoomDepth: Double = 2.1,
        mode: ZoomMode = .followCursor,
        transitionPreset: ZoomTransitionPreset = .quick,
        isAutoGenerated: Bool = false
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.zoomDepth = zoomDepth
        self.mode = mode
        self.transitionPreset = transitionPreset
        self.isAutoGenerated = isAutoGenerated
    }
}

// MARK: - Timeline Clips & Speed Ramps

public struct ClipSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var sourceStartTime: TimeInterval
    public var sourceEndTime: TimeInterval
    public var speedMultiplier: Double
    public var isMuted: Bool

    public var sourceDuration: TimeInterval {
        max(0.05, sourceEndTime - sourceStartTime)
    }

    public var timelineDuration: TimeInterval {
        sourceDuration / max(0.25, speedMultiplier)
    }

    public init(
        id: UUID = UUID(),
        label: String = "Screen Clip",
        sourceStartTime: TimeInterval,
        sourceEndTime: TimeInterval,
        speedMultiplier: Double = 1.0,
        isMuted: Bool = false
    ) {
        self.id = id
        self.label = label
        self.sourceStartTime = sourceStartTime
        self.sourceEndTime = sourceEndTime
        self.speedMultiplier = speedMultiplier
        self.isMuted = isMuted
    }
}

public struct SpeedRampSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var speedMultiplier: Double
    public var easeDuration: TimeInterval

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        speedMultiplier: Double = 2.0,
        easeDuration: TimeInterval = 0.25
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.speedMultiplier = speedMultiplier
        self.easeDuration = easeDuration
    }
}

// MARK: - Webcam PiP Overlay

public enum WebcamShape: String, Codable, CaseIterable, Identifiable, Sendable {
    case circle = "Circle"
    case squircle = "Squircle"
    case landscape16x9 = "16:9 Wide"
    case classic4x3 = "4:3 Box"
    case verticalPill = "Vertical Pill"

    public var id: String { rawValue }
}

public enum WebcamCorner: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottomRight = "Bottom Right"
    case bottomLeft = "Bottom Left"
    case topRight = "Top Right"
    case topLeft = "Top Left"
    case custom = "Custom Drag"

    public var id: String { rawValue }
}

public struct WebcamSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var shape: WebcamShape
    public var corner: WebcamCorner
    public var customNormalizedCenter: CGPoint
    /// Diameter/width as a fraction of canvas height [0.12 ... 0.42].
    public var scale: Double
    public var borderWidth: Double
    public var borderColor: CodableColor
    public var shadowOpacity: Double
    public var isMirrored: Bool
    /// Smoothly shrink webcam bubble when camera zooms into the same corner.
    public var autoDuckOnZoom: Bool

    public init(
        isEnabled: Bool = true,
        shape: WebcamShape = .squircle,
        corner: WebcamCorner = .bottomRight,
        customNormalizedCenter: CGPoint = CGPoint(x: 0.85, y: 0.82),
        scale: Double = 0.22,
        borderWidth: Double = 3.0,
        borderColor: CodableColor = CodableColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.85),
        shadowOpacity: Double = 0.55,
        isMirrored: Bool = true,
        autoDuckOnZoom: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.shape = shape
        self.corner = corner
        self.customNormalizedCenter = customNormalizedCenter
        self.scale = scale
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.shadowOpacity = shadowOpacity
        self.isMirrored = isMirrored
        self.autoDuckOnZoom = autoDuckOnZoom
    }
}

// MARK: - Multi-Track Audio Settings

public struct AudioSettings: Codable, Equatable, Sendable {
    /// Gain in [0.0 ... 2.0].
    public var micVolume: Double
    public var systemVolume: Double
    public var isMicMuted: Bool
    public var isSystemMuted: Bool
    public var voiceIsolation: Bool
    public var autoDuckSystemAudio: Bool
    public var duckingAmountDB: Double
    public var micWaveformSamples: [Float]
    public var sysWaveformSamples: [Float]

    public init(
        micVolume: Double = 1.0,
        systemVolume: Double = 0.85,
        isMicMuted: Bool = false,
        isSystemMuted: Bool = false,
        voiceIsolation: Bool = true,
        autoDuckSystemAudio: Bool = true,
        duckingAmountDB: Double = -12.0,
        micWaveformSamples: [Float] = [],
        sysWaveformSamples: [Float] = []
    ) {
        self.micVolume = micVolume
        self.systemVolume = systemVolume
        self.isMicMuted = isMicMuted
        self.isSystemMuted = isSystemMuted
        self.voiceIsolation = voiceIsolation
        self.autoDuckSystemAudio = autoDuckSystemAudio
        self.duckingAmountDB = duckingAmountDB
        self.micWaveformSamples = micWaveformSamples
        self.sysWaveformSamples = sysWaveformSamples
    }
}

// MARK: - Keystroke Visualizer Settings

public enum OverlayPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case bottomCenter = "Bottom Center"
    case topCenter = "Top Center"
    case bottomLeft = "Bottom Left"
    case topRight = "Top Right"

    public var id: String { rawValue }
}

public enum KeystrokeTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case darkGlass = "Dark Glass"
    case lightGlass = "Light Glass"
    case highContrast = "High Contrast"

    public var id: String { rawValue }
}

public struct KeystrokeOverlaySettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var shortcutsOnly: Bool
    public var position: OverlayPosition
    public var theme: KeystrokeTheme
    public var fontSize: Double
    public var holdDurationSeconds: Double

    public init(
        isEnabled: Bool = true,
        shortcutsOnly: Bool = false,
        position: OverlayPosition = .bottomCenter,
        theme: KeystrokeTheme = .darkGlass,
        fontSize: Double = 18.0,
        holdDurationSeconds: Double = 1.6
    ) {
        self.isEnabled = isEnabled
        self.shortcutsOnly = shortcutsOnly
        self.position = position
        self.theme = theme
        self.fontSize = fontSize
        self.holdDurationSeconds = holdDurationSeconds
    }
}

// MARK: - Auto-Captions & Transcript

public struct CaptionWord: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var word: String
    public var startTime: TimeInterval
    public var endTime: TimeInterval

    public init(id: UUID = UUID(), word: String, startTime: TimeInterval, endTime: TimeInterval) {
        self.id = id
        self.word = word
        self.startTime = startTime
        self.endTime = endTime
    }
}

public struct CaptionSegment: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var startTime: TimeInterval
    public var endTime: TimeInterval
    public var text: String
    public var words: [CaptionWord]

    public init(
        id: UUID = UUID(),
        startTime: TimeInterval,
        endTime: TimeInterval,
        text: String,
        words: [CaptionWord] = []
    ) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
        self.text = text
        self.words = words
    }
}

public struct CaptionStyleSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var fontSize: Double
    public var pillBackgroundOpacity: Double
    public var activeWordHighlightColor: CodableColor
    /// Normalized vertical position [0.15 ... 0.92].
    public var verticalPosition: Double

    public init(
        isEnabled: Bool = true,
        fontSize: Double = 24.0,
        pillBackgroundOpacity: Double = 0.72,
        activeWordHighlightColor: CodableColor = CodableColor(red: 0.35, green: 0.78, blue: 1.0),
        verticalPosition: Double = 0.88
    ) {
        self.isEnabled = isEnabled
        self.fontSize = fontSize
        self.pillBackgroundOpacity = pillBackgroundOpacity
        self.activeWordHighlightColor = activeWordHighlightColor
        self.verticalPosition = verticalPosition
    }
}

// MARK: - Export Configuration

public enum ExportFormat: String, Codable, CaseIterable, Identifiable, Sendable {
    case mp4H264 = "MP4 (H.264)"
    case mp4HEVC = "MP4 / MOV (HEVC)"
    case webM = "WebM (VP9)"
    case gif = "Animated GIF"

    public var id: String { rawValue }

    public var fileExtension: String {
        switch self {
        case .mp4H264, .mp4HEVC: return "mp4"
        case .webM: return "webm"
        case .gif: return "gif"
        }
    }
}

public enum ExportResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case p720 = "720p HD"
    case p1080 = "1080p Full HD"
    case p1440 = "1440p QHD"
    case p4K = "4K UHD (2160p)"

    public var id: String { rawValue }

    public var baseHeight: CGFloat {
        switch self {
        case .p720: return 720
        case .p1080: return 1080
        case .p1440: return 1440
        case .p4K: return 2160
        }
    }
}

public enum ExportQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case webOptimized = "Web Optimized"
    case high = "High Quality"
    case studioMaster = "Studio Master"

    public var id: String { rawValue }

    public var bitsPerPixel: Double {
        switch self {
        case .webOptimized: return 0.08
        case .high: return 0.16
        case .studioMaster: return 0.32
        }
    }
}

public struct ExportSettings: Codable, Equatable, Sendable {
    public var format: ExportFormat
    public var resolution: ExportResolution
    public var fps: Int
    public var quality: ExportQuality
    public var cloudUploadEndpoint: String

    public init(
        format: ExportFormat = .mp4HEVC,
        resolution: ExportResolution = .p1080,
        fps: Int = 60,
        quality: ExportQuality = .high,
        cloudUploadEndpoint: String = "https://share.displaystudio.local/upload"
    ) {
        self.format = format
        self.resolution = resolution
        self.fps = fps
        self.quality = quality
        self.cloudUploadEndpoint = cloudUploadEndpoint
    }
}
