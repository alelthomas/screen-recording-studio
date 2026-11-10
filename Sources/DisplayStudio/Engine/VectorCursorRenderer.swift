import Foundation
import CoreGraphics
import AppKit

public enum VectorCursorRenderer {

    /// Draws a resolution-independent vector macOS cursor at the specified screen-space point (`origin` in top-left coordinate system).
    public static func drawCursor(
        in ctx: CGContext,
        style: CursorStyle,
        at point: CGPoint,
        scale: CGFloat,
        opacity: CGFloat
    ) {
        guard opacity > 0.01 else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        ctx.setAlpha(opacity)
        ctx.translateBy(x: point.x, y: point.y)
        ctx.scaleBy(x: scale, y: scale)

        // Subtle cursor drop shadow
        ctx.setShadow(
            offset: CGSize(width: 0, height: 2.5),
            blur: 5.5,
            color: NSColor(calibratedWhite: 0.0, alpha: 0.55).cgColor
        )

        switch style {
        case .arrow:
            drawArrowCursor(in: ctx)
        case .pointingHand:
            drawPointingHandCursor(in: ctx)
        case .iBeam:
            drawIBeamCursor(in: ctx)
        case .crosshair:
            drawCrosshairCursor(in: ctx)
        case .openHand, .closedHand:
            drawHandGrabCursor(in: ctx, isClosed: style == .closedHand)
        case .resizeLeftRight:
            drawResizeCursor(in: ctx, horizontal: true)
        case .resizeUpDown:
            drawResizeCursor(in: ctx, horizontal: false)
        }
    }

    public static func drawClickRipples(
        in ctx: CGContext,
        ripples: [ActiveClickRipple],
        screenFrameRect: CGRect,
        cameraCenter: CGPoint,
        cameraZoom: CGFloat,
        rippleColor: CodableColor
    ) {
        guard !ripples.isEmpty else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        for ripple in ripples {
            let canvasPoint = projectNormalizedToScreenRect(
                ripple.normalizedPos,
                in: screenFrameRect,
                cameraCenter: cameraCenter,
                cameraZoom: cameraZoom
            )
            let p = CGFloat(min(1.0, max(0.0, ripple.progress)))
            let easeOut = 1.0 - pow(1.0 - p, 3.0)
            let maxRadius: CGFloat = 46.0 * sqrt(max(1.0, cameraZoom))
            let radius = 8.0 + maxRadius * easeOut
            let alpha = CGFloat(rippleColor.alpha) * (1.0 - easeOut)

            let strokeColor = NSColor(
                srgbRed: rippleColor.red,
                green: rippleColor.green,
                blue: rippleColor.blue,
                alpha: alpha
            ).cgColor

            let fillColor = NSColor(
                srgbRed: rippleColor.red,
                green: rippleColor.green,
                blue: rippleColor.blue,
                alpha: alpha * 0.24
            ).cgColor

            let ringRect = CGRect(
                x: canvasPoint.x - radius,
                y: canvasPoint.y - radius,
                width: radius * 2.0,
                height: radius * 2.0
            )
            ctx.setFillColor(fillColor)
            ctx.fillEllipse(in: ringRect)

            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(3.0 * (1.0 - p * 0.45))
            ctx.strokeEllipse(in: ringRect)
        }
    }

    public static func projectNormalizedToScreenRect(
        _ normalized: CGPoint,
        in screenRect: CGRect,
        cameraCenter: CGPoint,
        cameraZoom: CGFloat
    ) -> CGPoint {
        let zoom = max(1.0, cameraZoom)
        let relX = (normalized.x - cameraCenter.x) * zoom + 0.5
        let relY = (normalized.y - cameraCenter.y) * zoom + 0.5
        return CGPoint(
            x: screenRect.minX + relX * screenRect.width,
            y: screenRect.minY + relY * screenRect.height
        )
    }

    // MARK: - Individual Vector Cursor Paths (Top-Left Origin Coordinates)

    private static func drawArrowCursor(in ctx: CGContext) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: 21.5))
        path.addLine(to: CGPoint(x: 5.2, y: 16.6))
        path.addLine(to: CGPoint(x: 9.0, y: 24.5))
        path.addLine(to: CGPoint(x: 12.2, y: 23.0))
        path.addLine(to: CGPoint(x: 8.4, y: 15.2))
        path.addLine(to: CGPoint(x: 15.2, y: 15.2))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(2.1)
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
    }

    private static func drawPointingHandCursor(in ctx: CGContext) {
        let path = CGMutablePath()
        // Finger tip at (0, 0)
        path.move(to: CGPoint(x: -2.0, y: 2.0))
        path.addArc(center: CGPoint(x: 0, y: 2.0), radius: 2.2, startAngle: .pi, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: 2.2, y: 9.5))
        path.addLine(to: CGPoint(x: 10.5, y: 9.5))
        path.addArc(center: CGPoint(x: 10.5, y: 12.5), radius: 3.0, startAngle: -.pi / 2, endAngle: 0, clockwise: false)
        path.addLine(to: CGPoint(x: 13.5, y: 19.5))
        path.addArc(center: CGPoint(x: 4.5, y: 19.5), radius: 9.0, startAngle: 0, endAngle: .pi, clockwise: false)
        path.addLine(to: CGPoint(x: -6.5, y: 12.5))
        path.addLine(to: CGPoint(x: -2.0, y: 10.0))
        path.closeSubpath()

        ctx.addPath(path)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.9)
        ctx.setLineJoin(.round)
        ctx.drawPath(using: .fillStroke)
    }

    private static func drawIBeamCursor(in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(3.4)
        ctx.setLineCap(.round)
        drawIBeamGeometry(in: ctx)

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.6)
        drawIBeamGeometry(in: ctx)
    }

    private static func drawIBeamGeometry(in ctx: CGContext) {
        ctx.move(to: CGPoint(x: 0, y: -9))
        ctx.addLine(to: CGPoint(x: 0, y: 9))
        ctx.move(to: CGPoint(x: -4.5, y: -9))
        ctx.addLine(to: CGPoint(x: 4.5, y: -9))
        ctx.move(to: CGPoint(x: -4.5, y: 9))
        ctx.addLine(to: CGPoint(x: 4.5, y: 9))
        ctx.strokePath()
    }

    private static func drawCrosshairCursor(in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(3.4)
        ctx.move(to: CGPoint(x: -10, y: 0))
        ctx.addLine(to: CGPoint(x: 10, y: 0))
        ctx.move(to: CGPoint(x: 0, y: -10))
        ctx.addLine(to: CGPoint(x: 0, y: 10))
        ctx.strokePath()

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.6)
        ctx.move(to: CGPoint(x: -10, y: 0))
        ctx.addLine(to: CGPoint(x: 10, y: 0))
        ctx.move(to: CGPoint(x: 0, y: -10))
        ctx.addLine(to: CGPoint(x: 0, y: 10))
        ctx.strokePath()
    }

    private static func drawHandGrabCursor(in ctx: CGContext, isClosed: Bool) {
        let radius: CGFloat = isClosed ? 7.5 : 9.0
        let rect = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(2.0)
        ctx.fillEllipse(in: rect)
        ctx.strokeEllipse(in: rect)
    }

    private static func drawResizeCursor(in ctx: CGContext, horizontal: Bool) {
        ctx.saveGState()
        if !horizontal {
            ctx.rotate(by: .pi / 2)
        }
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(3.5)
        ctx.move(to: CGPoint(x: -11, y: 0))
        ctx.addLine(to: CGPoint(x: 11, y: 0))
        ctx.strokePath()

        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setLineWidth(1.8)
        ctx.move(to: CGPoint(x: -11, y: 0))
        ctx.addLine(to: CGPoint(x: 11, y: 0))
        ctx.strokePath()
        ctx.restoreGState()
    }
}
