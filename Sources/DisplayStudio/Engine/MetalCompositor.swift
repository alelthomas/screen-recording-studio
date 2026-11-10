import Foundation
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Metal
import MetalKit
import AVFoundation
import AppKit

public final class MetalCompositor {
    public let device: MTLDevice?
    public let commandQueue: MTLCommandQueue?
    public let ciContext: CIContext
    private var pipelineState: MTLRenderPipelineState?

    private var cachedCustomBackdropURL: String?
    private var cachedCustomBackdropImage: CIImage?

    private var cachedScreenAssetURL: URL?
    private var screenImageGenerator: AVAssetImageGenerator?
    private var cachedWebcamAssetURL: URL?
    private var webcamImageGenerator: AVAssetImageGenerator?

    public init() {
        let mtlDevice = MTLCreateSystemDefaultDevice()
        self.device = mtlDevice
        self.commandQueue = mtlDevice?.makeCommandQueue()
        if let mtlDevice {
            self.ciContext = CIContext(mtlDevice: mtlDevice, options: [
                .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any,
                .cacheIntermediates: false
            ])
        } else {
            self.ciContext = CIContext()
        }
        compileMetalShaderPipeline()
    }

    private func compileMetalShaderPipeline() {
        guard let device else { return }
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut {
            float4 position [[position]];
            float2 uv;
        };
        struct MotionBlurUniforms {
            float2 velocityUV;
            float intensity;
            float zoomFactor;
            float vignetteIntensity;
            float brightnessOffset;
        };
        vertex VertexOut fullscreenQuadVertex(uint vertexID [[vertex_id]]) {
            constexpr float2 positions[4] = {
                float2(-1.0, -1.0), float2( 1.0, -1.0),
                float2(-1.0,  1.0), float2( 1.0,  1.0)
            };
            constexpr float2 uvs[4] = {
                float2(0.0, 1.0), float2(1.0, 1.0),
                float2(0.0, 0.0), float2(1.0, 0.0)
            };
            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            out.uv = uvs[vertexID];
            return out;
        }
        fragment float4 directionalMotionBlurFragment(
            VertexOut in [[stage_in]],
            texture2d<float, access::sample> sourceTexture [[texture(0)]],
            constant MotionBlurUniforms &uniforms [[buffer(0)]]
        ) {
            constexpr sampler texSampler(coord::normalized, address::clamp_to_edge, filter::linear);
            float2 uv = in.uv;
            float2 vel = uniforms.velocityUV * uniforms.intensity;
            float speed = length(vel);
            float4 accum = float4(0.0);
            if (speed < 0.0004) {
                accum = sourceTexture.sample(texSampler, uv);
            } else {
                constexpr int SAMPLES = 12;
                float weightSum = 0.0;
                for (int i = 0; i < SAMPLES; ++i) {
                    float t = (float(i) / float(SAMPLES - 1)) - 0.5;
                    float2 sampleUV = clamp(uv + vel * t, float2(0.001), float2(0.999));
                    float w = 1.0 - abs(t) * 0.65;
                    accum += sourceTexture.sample(texSampler, sampleUV) * w;
                    weightSum += w;
                }
                accum /= max(weightSum, 0.001);
            }
            float2 centered = uv - float2(0.5, 0.5);
            float distSq = dot(centered, centered);
            float vignette = 1.0 - clamp(distSq * uniforms.vignetteIntensity * 1.4, 0.0, 0.65);
            accum.rgb = clamp((accum.rgb + uniforms.brightnessOffset) * vignette, 0.0, 1.0);
            return accum;
        }
        """

        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "fullscreenQuadVertex")
            desc.fragmentFunction = library.makeFunction(name: "directionalMotionBlurFragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            // Fallback to CoreImage motion blur if shader compilation fails
            self.pipelineState = nil
        }
    }

    // MARK: - Compute Screen Card Rect inside Canvas

    public static func computeScreenFrameRect(
        canvasSize: CGSize,
        sourceSize: CGSize,
        paddingRatio: Double
    ) -> CGRect {
        let pad = CGFloat(min(0.35, max(0.0, paddingRatio)))
        let availWidth = max(64, canvasSize.width * (1.0 - pad * 2.0))
        let availHeight = max(64, canvasSize.height * (1.0 - pad * 2.0))
        let srcAspect = max(0.25, sourceSize.width / max(1.0, sourceSize.height))
        let availAspect = availWidth / availHeight

        let fitWidth: CGFloat
        let fitHeight: CGFloat
        if srcAspect > availAspect {
            fitWidth = availWidth
            fitHeight = availWidth / srcAspect
        } else {
            fitHeight = availHeight
            fitWidth = availHeight * srcAspect
        }

        return CGRect(
            x: (canvasSize.width - fitWidth) * 0.5,
            y: (canvasSize.height - fitHeight) * 0.5,
            width: fitWidth,
            height: fitHeight
        )
    }

    // MARK: - Main Frame Compositing Entry Point

    public func renderCompositeFrame(
        project: StudioProject,
        frameState: EvaluatedFrameState,
        canvasSize: CGSize,
        bundleURL: URL? = nil,
        liveWebcamImage: CGImage? = nil
    ) -> CGImage? {
        let width = max(64, Int(canvasSize.width))
        let height = max(64, Int(canvasSize.height))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            return nil
        }

        // Flip to top-left origin so all studio coordinates match normalized screen coordinates (0,0 = top-left)
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1.0, y: -1.0)

        let fullRect = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        let scaleFactor = CGFloat(height) / 1080.0

        // 1. Draw Background (Wallpaper / Gradient / Mesh / Solid / Blurred Image)
        drawBackground(in: ctx, rect: fullRect, config: project.background)

        // 2. Compute Screen Frame Rect
        let screenRect = Self.computeScreenFrameRect(
            canvasSize: fullRect.size,
            sourceSize: project.telemetry.sourceSize,
            paddingRatio: project.frameStyling.paddingRatio
        )
        let cornerRadius = CGFloat(project.frameStyling.cornerRadius) * scaleFactor

        // 3. Draw Drop Shadow behind Screen Frame
        if project.frameStyling.shadowOpacity > 0.01 {
            ctx.saveGState()
            let shadowOffset = CGSize(
                width: 0,
                height: -CGFloat(project.frameStyling.shadowOffsetY) * scaleFactor
            )
            ctx.setShadow(
                offset: shadowOffset,
                blur: CGFloat(project.frameStyling.shadowRadius) * scaleFactor,
                color: NSColor(calibratedWhite: 0.0, alpha: CGFloat(project.frameStyling.shadowOpacity)).cgColor
            )
            let shadowPath = CGPath(
                roundedRect: screenRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            ctx.addPath(shadowPath)
            ctx.setFillColor(NSColor(calibratedWhite: 0.08, alpha: 1.0).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // 4. Render Screen Content + Camera Zoom/Pan + Directional Motion Blur + Cursor + Click Ripples
        ctx.saveGState()
        let clipPath = CGPath(
            roundedRect: screenRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(clipPath)
        ctx.clip()

        drawZoomedScreenAndCursor(
            in: ctx,
            screenRect: screenRect,
            project: project,
            frameState: frameState,
            scaleFactor: scaleFactor,
            bundleURL: bundleURL
        )
        ctx.restoreGState()

        // 5. Draw Subtle Glass Inset Border around Screen Frame
        if project.frameStyling.insetBorderWidth > 0.1 && project.frameStyling.insetBorderOpacity > 0.01 {
            ctx.saveGState()
            let borderPath = CGPath(
                roundedRect: screenRect.insetBy(dx: 0.5, dy: 0.5),
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            ctx.addPath(borderPath)
            ctx.setStrokeColor(
                NSColor(calibratedWhite: 1.0, alpha: CGFloat(project.frameStyling.insetBorderOpacity)).cgColor
            )
            ctx.setLineWidth(CGFloat(project.frameStyling.insetBorderWidth) * scaleFactor)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // 6. Draw Webcam Picture-in-Picture (PiP) Overlay
        if project.webcamSettings.isEnabled {
            drawWebcamOverlay(
                in: ctx,
                canvasRect: fullRect,
                settings: project.webcamSettings,
                duckScale: frameState.webcamDuckScale,
                sourceTime: frameState.sourceTime,
                scaleFactor: scaleFactor,
                bundleURL: bundleURL,
                webcamFilename: project.webcamVideoFilename,
                liveWebcamImage: liveWebcamImage
            )
        }

        // 7. Draw Keystroke & Shortcut Visualizer Badge
        if project.keystrokeSettings.isEnabled, let latestKey = frameState.activeKeystrokes.last {
            drawKeystrokeOverlay(
                in: ctx,
                canvasRect: fullRect,
                event: latestKey,
                settings: project.keystrokeSettings,
                currentTime: frameState.sourceTime,
                scaleFactor: scaleFactor
            )
        }

        // 8. Draw Auto-Captions with Active-Word Karaoke Highlight
        if project.captionStyle.isEnabled, let caption = frameState.activeCaption {
            drawCaptionOverlay(
                in: ctx,
                canvasRect: fullRect,
                caption: caption,
                style: project.captionStyle,
                currentTime: frameState.sourceTime,
                scaleFactor: scaleFactor
            )
        }

        return ctx.makeImage()
    }

    // MARK: - Write Directly to CVPixelBuffer for AVAssetWriter Export

    public func renderToPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        project: StudioProject,
        frameState: EvaluatedFrameState,
        bundleURL: URL? = nil
    ) {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let cgImage = renderCompositeFrame(
            project: project,
            frameState: frameState,
            canvasSize: CGSize(width: width, height: height),
            bundleURL: bundleURL
        ) else { return }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        if let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    // MARK: - Background Rendering

    private func drawBackground(in ctx: CGContext, rect: CGRect, config: BackgroundConfig) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        switch config.mode {
        case .solid:
            ctx.setFillColor(config.solidColor.nsColor.cgColor)
            ctx.fill(rect)

        case .gradient:
            let colors = [config.gradientStart.nsColor.cgColor, config.gradientEnd.nsColor.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
                let rad = config.gradientAngleDegrees * .pi / 180.0
                let cx = rect.midX
                let cy = rect.midY
                let r = hypot(rect.width, rect.height) * 0.5
                let start = CGPoint(x: cx - cos(rad) * r, y: cy - sin(rad) * r)
                let end = CGPoint(x: cx + cos(rad) * r, y: cy + sin(rad) * r)
                ctx.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }

        case .wallpaper, .mesh:
            let stopColors: [CodableColor] = (config.mode == .wallpaper)
                ? config.wallpaperPreset.colors
                : [config.gradientStart, config.gradientAccent, config.gradientEnd, config.gradientStart]

            let cgColors = stopColors.map { $0.nsColor.cgColor } as CFArray
            let locations: [CGFloat] = [0.0, 0.35, 0.72, 1.0]
            if let baseGrad = CGGradient(colorsSpace: colorSpace, colors: cgColors, locations: locations) {
                ctx.drawLinearGradient(
                    baseGrad,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: CGPoint(x: rect.maxX, y: rect.maxY),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            // Add luminous radial mesh orbs
            if stopColors.count >= 3 {
                let orbColor = stopColors[2]
                let orbColors = [
                    NSColor(srgbRed: orbColor.red, green: orbColor.green, blue: orbColor.blue, alpha: 0.52).cgColor,
                    NSColor(srgbRed: orbColor.red, green: orbColor.green, blue: orbColor.blue, alpha: 0.0).cgColor
                ] as CFArray
                if let radial = CGGradient(colorsSpace: colorSpace, colors: orbColors, locations: [0.0, 1.0]) {
                    let center = CGPoint(x: rect.width * 0.78, y: rect.height * 0.24)
                    ctx.drawRadialGradient(
                        radial,
                        startCenter: center,
                        startRadius: 0,
                        endCenter: center,
                        endRadius: max(rect.width, rect.height) * 0.58,
                        options: []
                    )
                }
            }

        case .customImage:
            if let path = config.customImagePath, !path.isEmpty,
               let cgImg = loadBlurredCustomBackdrop(path: path, blurRadius: config.backdropBlurRadius, targetSize: rect.size) {
                ctx.saveGState()
                ctx.translateBy(x: 0, y: rect.height)
                ctx.scaleBy(x: 1, y: -1)
                ctx.draw(cgImg, in: rect)
                ctx.restoreGState()
            } else {
                // Fallback to wallpaper if no custom image selected yet
                var fallback = config
                fallback.mode = .wallpaper
                drawBackground(in: ctx, rect: rect, config: fallback)
                return
            }
        }

        // Apply brightness & vignette overlay
        if abs(config.brightness) > 0.01 {
            if config.brightness > 0 {
                ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: CGFloat(min(0.6, config.brightness))).cgColor)
            } else {
                ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: CGFloat(min(0.7, -config.brightness))).cgColor)
            }
            ctx.fill(rect)
        }

        if config.vignetteIntensity > 0.01 {
            let vigAlpha = CGFloat(min(0.75, config.vignetteIntensity))
            let vigColors = [
                NSColor(calibratedWhite: 0.0, alpha: 0.0).cgColor,
                NSColor(calibratedWhite: 0.0, alpha: vigAlpha).cgColor
            ] as CFArray
            if let vigGrad = CGGradient(colorsSpace: colorSpace, colors: vigColors, locations: [0.45, 1.0]) {
                let center = CGPoint(x: rect.midX, y: rect.midY)
                ctx.drawRadialGradient(
                    vigGrad,
                    startCenter: center,
                    startRadius: min(rect.width, rect.height) * 0.25,
                    endCenter: center,
                    endRadius: hypot(rect.width, rect.height) * 0.55,
                    options: [.drawsAfterEndLocation]
                )
            }
        }
    }

    private func loadBlurredCustomBackdrop(path: String, blurRadius: Double, targetSize: CGSize) -> CGImage? {
        if cachedCustomBackdropURL != path || cachedCustomBackdropImage == nil {
            let url = URL(fileURLWithPath: path)
            cachedCustomBackdropImage = CIImage(contentsOf: url)
            cachedCustomBackdropURL = path
        }
        guard let baseCI = cachedCustomBackdropImage else { return nil }
        let extent = baseCI.extent
        guard extent.width > 1, extent.height > 1 else { return nil }

        var output = baseCI
        if blurRadius > 0.5 {
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = baseCI.clampedToExtent()
            blur.radius = Float(blurRadius)
            if let blurred = blur.outputImage?.cropped(to: extent) {
                output = blurred
            }
        }
        return ciContext.createCGImage(output, from: extent)
    }

    // MARK: - Zoomed Screen Content + Motion Blur + Cursor

    private func drawZoomedScreenAndCursor(
        in ctx: CGContext,
        screenRect: CGRect,
        project: StudioProject,
        frameState: EvaluatedFrameState,
        scaleFactor: CGFloat,
        bundleURL: URL?
    ) {
        let zoom = CGFloat(max(1.0, frameState.cameraZoom))
        let camCenter = frameState.cameraCenter

        // Check if we have a real recorded screen video frame on disk
        let realVideoFrame = decodeVideoFrame(
            bundleURL: bundleURL,
            filename: project.screenVideoFilename,
            at: frameState.sourceTime,
            isWebcam: false
        )

        ctx.saveGState()
        // Apply camera zoom & pan transform relative to screenRect
        let originX = screenRect.minX + (0.5 - camCenter.x * zoom) * screenRect.width
        let originY = screenRect.minY + (0.5 - camCenter.y * zoom) * screenRect.height
        let zoomedRect = CGRect(
            x: originX,
            y: originY,
            width: screenRect.width * zoom,
            height: screenRect.height * zoom
        )

        // Compute directional motion blur if camera velocity is significant
        let camSpeed = hypot(frameState.cameraVelocity.dx, frameState.cameraVelocity.dy)
        let blurStrength = project.cursorSettings.motionBlurIntensity * (project.cursorSettings.shutterAngleDegrees / 180.0)

        if let realFrame = realVideoFrame {
            let imageToDraw: CGImage
            if camSpeed > 0.08 && blurStrength > 0.05,
               let blurred = applyDirectionalMotionBlur(
                to: realFrame,
                velocity: frameState.cameraVelocity,
                strength: blurStrength
               ) {
                imageToDraw = blurred
            } else {
                imageToDraw = realFrame
            }
            ctx.saveGState()
            ctx.translateBy(x: zoomedRect.minX, y: zoomedRect.maxY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            ctx.draw(imageToDraw, in: CGRect(origin: .zero, size: zoomedRect.size))
            ctx.restoreGState()
        } else {
            // Render built-in interactive macOS App / IDE Studio simulation scene
            drawSimulatedMacOSScreen(
                in: ctx,
                rect: zoomedRect,
                sourceTime: frameState.sourceTime,
                cameraVelocity: frameState.cameraVelocity,
                motionBlurStrength: blurStrength
            )
        }
        ctx.restoreGState()

        // Draw click ripples in zoomed screen space
        VectorCursorRenderer.drawClickRipples(
            in: ctx,
            ripples: frameState.activeRipples,
            screenFrameRect: screenRect,
            cameraCenter: camCenter,
            cameraZoom: zoom,
            rippleColor: project.cursorSettings.rippleColor
        )

        // Project smoothed cursor into zoomed screen space and draw crisp vector cursor
        let cursorCanvasPos = VectorCursorRenderer.projectNormalizedToScreenRect(
            frameState.smoothedCursorPos,
            in: screenRect,
            cameraCenter: camCenter,
            cameraZoom: zoom
        )
        let cursorTotalScale = CGFloat(project.cursorSettings.scale * frameState.cursorClickScale) * scaleFactor * sqrt(zoom)

        // Optional motion-blur trail ghosting on rapid cursor sweeps
        let curSpeed = hypot(frameState.cursorVelocity.dx, frameState.cursorVelocity.dy)
        if curSpeed > 0.45 && blurStrength > 0.1 && frameState.cursorOpacity > 0.1 {
            for ghostIdx in 1...3 {
                let lag = CGFloat(ghostIdx) * 0.012 * CGFloat(blurStrength)
                let ghostNorm = CGPoint(
                    x: frameState.smoothedCursorPos.x - frameState.cursorVelocity.dx * lag,
                    y: frameState.smoothedCursorPos.y - frameState.cursorVelocity.dy * lag
                )
                let ghostPt = VectorCursorRenderer.projectNormalizedToScreenRect(
                    ghostNorm,
                    in: screenRect,
                    cameraCenter: camCenter,
                    cameraZoom: zoom
                )
                VectorCursorRenderer.drawCursor(
                    in: ctx,
                    style: frameState.cursorStyle,
                    at: ghostPt,
                    scale: cursorTotalScale,
                    opacity: CGFloat(frameState.cursorOpacity) * (0.24 / CGFloat(ghostIdx))
                )
            }
        }

        VectorCursorRenderer.drawCursor(
            in: ctx,
            style: frameState.cursorStyle,
            at: cursorCanvasPos,
            scale: cursorTotalScale,
            opacity: CGFloat(frameState.cursorOpacity)
        )
    }

    private func applyDirectionalMotionBlur(
        to image: CGImage,
        velocity: CGVector,
        strength: Double
    ) -> CGImage? {
        let speed = hypot(velocity.dx, velocity.dy)
        let radius = min(28.0, speed * 26.0 * strength)
        guard radius > 1.2 else { return nil }

        let ciImg = CIImage(cgImage: image)
        let extent = ciImg.extent
        let angle = atan2(velocity.dy, velocity.dx)

        guard let filter = CIFilter(name: "CIMotionBlur") else { return nil }
        filter.setValue(ciImg.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        filter.setValue(angle, forKey: kCIInputAngleKey)

        guard let out = filter.outputImage?.cropped(to: extent) else { return nil }
        return ciContext.createCGImage(out, from: extent)
    }

    // MARK: - Simulated macOS App Screen (for Demo Project & Instant Preview)

    private func drawSimulatedMacOSScreen(
        in ctx: CGContext,
        rect: CGRect,
        sourceTime: TimeInterval,
        cameraVelocity: CGVector,
        motionBlurStrength: Double
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let w = rect.width
        let h = rect.height
        let ox = rect.minX
        let oy = rect.minY

        // App window dark surface
        ctx.setFillColor(NSColor(srgbRed: 0.08, green: 0.09, blue: 0.13, alpha: 1.0).cgColor)
        ctx.fill(rect)

        // Top macOS titlebar
        let titleBarH = h * 0.065
        let titleBarRect = CGRect(x: ox, y: oy, width: w, height: titleBarH)
        ctx.setFillColor(NSColor(srgbRed: 0.12, green: 0.13, blue: 0.18, alpha: 1.0).cgColor)
        ctx.fill(titleBarRect)

        // Traffic light window controls
        let dotY = oy + titleBarH * 0.5
        let dotR = h * 0.0085
        let trafficColors: [NSColor] = [
            NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1.0),
            NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1.0),
            NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1.0)
        ]
        for (idx, col) in trafficColors.enumerated() {
            let dotX = ox + w * 0.022 + CGFloat(idx) * (dotR * 3.1)
            ctx.setFillColor(col.cgColor)
            ctx.fillEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))
        }

        // Top-right action button ("Export 4K" at (0.82, 0.18) region)
        let exportBtnRect = CGRect(x: ox + w * 0.75, y: oy + h * 0.13, width: w * 0.16, height: h * 0.075)
        let isExportHovered = sourceTime >= 7.8 && sourceTime <= 10.5
        let exportBtnColor = isExportHovered
            ? NSColor(srgbRed: 0.32, green: 0.58, blue: 1.0, alpha: 1.0)
            : NSColor(srgbRed: 0.22, green: 0.44, blue: 0.92, alpha: 0.92)
        let exportPath = CGPath(roundedRect: exportBtnRect, cornerWidth: h * 0.015, cornerHeight: h * 0.015, transform: nil)
        ctx.addPath(exportPath)
        ctx.setFillColor(exportBtnColor.cgColor)
        ctx.fillPath()
        drawSimpleText("✦ Export 4K 60fps", in: ctx, rect: exportBtnRect, fontSize: h * 0.024, color: .white, alignCenter: true)

        // Left navigation sidebar
        let sidebarW = w * 0.24
        let sidebarRect = CGRect(x: ox, y: oy + titleBarH, width: sidebarW, height: h - titleBarH)
        ctx.setFillColor(NSColor(srgbRed: 0.10, green: 0.11, blue: 0.16, alpha: 1.0).cgColor)
        ctx.fill(sidebarRect)

        let navItems = [
            ("🎬  Screen Capture", 0.19),
            ("🎯  Cursor & Spring", 0.31),
            ("🖼  Backgrounds", 0.43),
            ("💬  Auto-Captions", 0.55),
            ("⚡️  Speed Ramps", 0.67)
        ]
        for (idx, item) in navItems.enumerated() {
            let itemRect = CGRect(
                x: ox + w * 0.018,
                y: oy + h * CGFloat(item.1),
                width: sidebarW - w * 0.036,
                height: h * 0.072
            )
            let isSelected = (idx == 0 && sourceTime < 2.6) || (idx == 1 && sourceTime >= 2.6)
            if isSelected {
                let selPath = CGPath(roundedRect: itemRect, cornerWidth: h * 0.012, cornerHeight: h * 0.012, transform: nil)
                ctx.addPath(selPath)
                ctx.setFillColor(NSColor(srgbRed: 0.26, green: 0.47, blue: 0.96, alpha: 0.28).cgColor)
                ctx.fillPath()
            }
            drawSimpleText(
                item.0,
                in: ctx,
                rect: itemRect.insetBy(dx: w * 0.014, dy: h * 0.016),
                fontSize: h * 0.022,
                color: isSelected ? .white : NSColor(calibratedWhite: 0.72, alpha: 1.0),
                alignCenter: false
            )
        }

        // Center Search / Command Bar around (0.54, 0.28)
        let searchRect = CGRect(x: ox + w * 0.30, y: oy + h * 0.23, width: w * 0.42, height: h * 0.085)
        let searchFocused = sourceTime >= 4.2 && sourceTime <= 7.2
        let searchPath = CGPath(roundedRect: searchRect, cornerWidth: h * 0.016, cornerHeight: h * 0.016, transform: nil)
        ctx.addPath(searchPath)
        ctx.setFillColor(NSColor(srgbRed: 0.14, green: 0.16, blue: 0.22, alpha: 1.0).cgColor)
        ctx.fillPath()
        ctx.addPath(searchPath)
        ctx.setStrokeColor(
            (searchFocused
                ? NSColor(srgbRed: 0.38, green: 0.68, blue: 1.0, alpha: 0.95)
                : NSColor(calibratedWhite: 1.0, alpha: 0.15)).cgColor
        )
        ctx.setLineWidth(h * 0.003)
        ctx.strokePath()

        let typedString: String = {
            let full = "ScreenCaptureKit + Metal 120Hz"
            if sourceTime < 4.4 { return "🔍  Search API or press ⌘K..." }
            let progress = min(1.0, max(0.0, (sourceTime - 4.4) / 1.8))
            let charCount = Int(Double(full.count) * progress)
            let prefix = String(full.prefix(charCount))
            return "🔍  \(prefix)|"
        }()
        drawSimpleText(
            typedString,
            in: ctx,
            rect: searchRect.insetBy(dx: w * 0.018, dy: h * 0.022),
            fontSize: h * 0.024,
            color: sourceTime < 4.4 ? NSColor(calibratedWhite: 0.58, alpha: 1.0) : .white,
            alignCenter: false
        )

        // Code / Telemetry cards in main workspace area
        let cardRect = CGRect(x: ox + w * 0.30, y: oy + h * 0.36, width: w * 0.61, height: h * 0.52)
        let cardPath = CGPath(roundedRect: cardRect, cornerWidth: h * 0.018, cornerHeight: h * 0.018, transform: nil)
        ctx.addPath(cardPath)
        ctx.setFillColor(NSColor(srgbRed: 0.11, green: 0.13, blue: 0.19, alpha: 1.0).cgColor)
        ctx.fillPath()

        let codeLines = [
            "let config = SCStreamConfiguration()",
            "config.showsCursor = false // Native cursor replaced by Vector Shader",
            "config.width = 3840; config.height = 2160",
            "config.minimumFrameInterval = CMTime(value: 1, timescale: 60)",
            "springSolver.integrate(stiffness: 180.0, damping: 26.0)"
        ]
        for (lineIdx, code) in codeLines.enumerated() {
            let lineRect = CGRect(
                x: cardRect.minX + w * 0.025,
                y: cardRect.minY + h * (0.05 + CGFloat(lineIdx) * 0.068),
                width: cardRect.width - w * 0.05,
                height: h * 0.05
            )
            drawSimpleText(
                code,
                in: ctx,
                rect: lineRect,
                fontSize: h * 0.021,
                color: lineIdx == 1
                    ? NSColor(srgbRed: 0.45, green: 0.88, blue: 0.68, alpha: 1.0)
                    : NSColor(calibratedWhite: 0.86, alpha: 1.0),
                alignCenter: false
            )
        }

        // Confirmation CTA pill around (0.64, 0.68)
        let confirmRect = CGRect(x: ox + w * 0.54, y: oy + h * 0.63, width: w * 0.22, height: h * 0.08)
        let isConfirmActive = sourceTime >= 9.6 && sourceTime <= 11.4
        let confirmPath = CGPath(roundedRect: confirmRect, cornerWidth: h * 0.016, cornerHeight: h * 0.016, transform: nil)
        ctx.addPath(confirmPath)
        ctx.setFillColor(
            (isConfirmActive
                ? NSColor(srgbRed: 0.22, green: 0.82, blue: 0.54, alpha: 0.95)
                : NSColor(srgbRed: 0.18, green: 0.22, blue: 0.32, alpha: 0.95)).cgColor
        )
        ctx.fillPath()
        drawSimpleText(
            isConfirmActive ? "✓ Render Complete" : "▶ Run Spring Solver",
            in: ctx,
            rect: confirmRect,
            fontSize: h * 0.022,
            color: .white,
            alignCenter: true
        )
    }

    // MARK: - Webcam PiP Overlay

    private func drawWebcamOverlay(
        in ctx: CGContext,
        canvasRect: CGRect,
        settings: WebcamSettings,
        duckScale: Double,
        sourceTime: TimeInterval,
        scaleFactor: CGFloat,
        bundleURL: URL?,
        webcamFilename: String?,
        liveWebcamImage: CGImage?
    ) {
        let baseDim = canvasRect.height * CGFloat(settings.scale) * CGFloat(duckScale)
        let size: CGSize = {
            switch settings.shape {
            case .circle, .squircle:
                return CGSize(width: baseDim, height: baseDim)
            case .landscape16x9:
                return CGSize(width: baseDim * 1.45, height: baseDim * 1.45 * 9.0 / 16.0)
            case .classic4x3:
                return CGSize(width: baseDim * 1.25, height: baseDim * 1.25 * 3.0 / 4.0)
            case .verticalPill:
                return CGSize(width: baseDim * 0.78, height: baseDim * 1.22)
            }
        }()

        let marginX = canvasRect.width * 0.038
        let marginY = canvasRect.height * 0.045
        let center: CGPoint = {
            switch settings.corner {
            case .bottomRight:
                return CGPoint(x: canvasRect.maxX - marginX - size.width * 0.5, y: canvasRect.maxY - marginY - size.height * 0.5)
            case .bottomLeft:
                return CGPoint(x: canvasRect.minX + marginX + size.width * 0.5, y: canvasRect.maxY - marginY - size.height * 0.5)
            case .topRight:
                return CGPoint(x: canvasRect.maxX - marginX - size.width * 0.5, y: canvasRect.minY + marginY + size.height * 0.5)
            case .topLeft:
                return CGPoint(x: canvasRect.minX + marginX + size.width * 0.5, y: canvasRect.minY + marginY + size.height * 0.5)
            case .custom:
                return CGPoint(
                    x: canvasRect.width * settings.customNormalizedCenter.x,
                    y: canvasRect.height * settings.customNormalizedCenter.y
                )
            }
        }()

        let pipRect = CGRect(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )

        let cornerRad: CGFloat = {
            switch settings.shape {
            case .circle, .verticalPill:
                return min(size.width, size.height) * 0.5
            case .squircle:
                return min(size.width, size.height) * 0.26
            case .landscape16x9, .classic4x3:
                return min(size.width, size.height) * 0.16
            }
        }()

        let clipPath = CGPath(roundedRect: pipRect, cornerWidth: cornerRad, cornerHeight: cornerRad, transform: nil)

        // Shadow
        if settings.shadowOpacity > 0.01 {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -8 * scaleFactor),
                blur: 24 * scaleFactor,
                color: NSColor(calibratedWhite: 0.0, alpha: CGFloat(settings.shadowOpacity)).cgColor
            )
            ctx.addPath(clipPath)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Content
        ctx.saveGState()
        ctx.addPath(clipPath)
        ctx.clip()

        let webcamFrame = liveWebcamImage ?? decodeVideoFrame(
            bundleURL: bundleURL,
            filename: webcamFilename,
            at: sourceTime,
            isWebcam: true
        )

        if let camImg = webcamFrame {
            ctx.saveGState()
            ctx.translateBy(x: pipRect.midX, y: pipRect.midY)
            if settings.isMirrored {
                ctx.scaleBy(x: -1.0, y: -1.0)
            } else {
                ctx.scaleBy(x: 1.0, y: -1.0)
            }
            ctx.draw(
                camImg,
                in: CGRect(x: -pipRect.width * 0.5, y: -pipRect.height * 0.5, width: pipRect.width, height: pipRect.height)
            )
            ctx.restoreGState()
        } else {
            // Presenter studio avatar placeholder
            let gradColors = [
                NSColor(srgbRed: 0.18, green: 0.24, blue: 0.38, alpha: 1.0).cgColor,
                NSColor(srgbRed: 0.09, green: 0.11, blue: 0.18, alpha: 1.0).cgColor
            ] as CFArray
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            if let grad = CGGradient(colorsSpace: colorSpace, colors: gradColors, locations: [0.0, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: pipRect.minX, y: pipRect.minY),
                    end: CGPoint(x: pipRect.maxX, y: pipRect.maxY),
                    options: []
                )
            }
            // Stylized presenter head & shoulders silhouette
            ctx.setFillColor(NSColor(srgbRed: 0.48, green: 0.72, blue: 1.0, alpha: 0.85).cgColor)
            let headR = min(pipRect.width, pipRect.height) * 0.18
            ctx.fillEllipse(
                in: CGRect(
                    x: pipRect.midX - headR,
                    y: pipRect.midY - headR * 1.35,
                    width: headR * 2,
                    height: headR * 2
                )
            )
            let shouldersW = pipRect.width * 0.62
            let shouldersH = pipRect.height * 0.42
            ctx.fillEllipse(
                in: CGRect(
                    x: pipRect.midX - shouldersW * 0.5,
                    y: pipRect.midY + headR * 0.85,
                    width: shouldersW,
                    height: shouldersH
                )
            )
        }
        ctx.restoreGState()

        // Border
        if settings.borderWidth > 0.1 {
            ctx.saveGState()
            ctx.addPath(clipPath)
            ctx.setStrokeColor(settings.borderColor.nsColor.cgColor)
            ctx.setLineWidth(CGFloat(settings.borderWidth) * scaleFactor)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: - Keystroke Visualizer Badge

    private func drawKeystrokeOverlay(
        in ctx: CGContext,
        canvasRect: CGRect,
        event: KeystrokeEvent,
        settings: KeystrokeOverlaySettings,
        currentTime: TimeInterval,
        scaleFactor: CGFloat
    ) {
        let elapsed = max(0, currentTime - event.timestamp)
        let hold = max(0.4, settings.holdDurationSeconds)
        let fadeAlpha: CGFloat = elapsed > (hold - 0.25) ? CGFloat(max(0, (hold - elapsed) / 0.25)) : 1.0
        guard fadeAlpha > 0.02 else { return }

        let fontSize = CGFloat(settings.fontSize) * scaleFactor * 1.25
        let label = event.displayLabel
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textSize = (label as NSString).size(withAttributes: attrs)

        let padX = 24.0 * scaleFactor
        let padY = 12.0 * scaleFactor
        let pillW = textSize.width + padX * 2.0
        let pillH = textSize.height + padY * 2.0

        let origin: CGPoint = {
            switch settings.position {
            case .bottomCenter:
                return CGPoint(x: (canvasRect.width - pillW) * 0.5, y: canvasRect.height * 0.78)
            case .topCenter:
                return CGPoint(x: (canvasRect.width - pillW) * 0.5, y: canvasRect.height * 0.06)
            case .bottomLeft:
                return CGPoint(x: canvasRect.width * 0.05, y: canvasRect.height * 0.78)
            case .topRight:
                return CGPoint(x: canvasRect.width * 0.95 - pillW, y: canvasRect.height * 0.06)
            }
        }()

        let pillRect = CGRect(x: origin.x, y: origin.y, width: pillW, height: pillH)
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: pillH * 0.38, cornerHeight: pillH * 0.38, transform: nil)

        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setAlpha(fadeAlpha)

        let bgColor: NSColor
        let fgColor: NSColor
        switch settings.theme {
        case .darkGlass:
            bgColor = NSColor(srgbRed: 0.08, green: 0.09, blue: 0.14, alpha: 0.86)
            fgColor = .white
        case .lightGlass:
            bgColor = NSColor(calibratedWhite: 0.96, alpha: 0.90)
            fgColor = .black
        case .highContrast:
            bgColor = NSColor.black
            fgColor = NSColor(srgbRed: 1.0, green: 0.86, blue: 0.24, alpha: 1.0)
        }

        ctx.addPath(pillPath)
        ctx.setFillColor(bgColor.cgColor)
        ctx.fillPath()

        ctx.addPath(pillPath)
        ctx.setStrokeColor(NSColor(calibratedWhite: 1.0, alpha: 0.24).cgColor)
        ctx.setLineWidth(1.5 * scaleFactor)
        ctx.strokePath()

        drawSimpleText(
            label,
            in: ctx,
            rect: pillRect.insetBy(dx: padX, dy: padY * 0.85),
            fontSize: fontSize,
            color: fgColor,
            alignCenter: true
        )
    }

    // MARK: - Auto-Caption Subtitle Overlay

    private func drawCaptionOverlay(
        in ctx: CGContext,
        canvasRect: CGRect,
        caption: CaptionSegment,
        style: CaptionStyleSettings,
        currentTime: TimeInterval,
        scaleFactor: CGFloat
    ) {
        let fontSize = CGFloat(style.fontSize) * scaleFactor
        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let fullText = caption.text
        let textSize = (fullText as NSString).size(withAttributes: [.font: font])

        let padX = 26.0 * scaleFactor
        let padY = 12.0 * scaleFactor
        let pillW = min(canvasRect.width * 0.86, textSize.width + padX * 2.0)
        let pillH = textSize.height + padY * 2.0
        let pillRect = CGRect(
            x: (canvasRect.width - pillW) * 0.5,
            y: canvasRect.height * CGFloat(style.verticalPosition) - pillH * 0.5,
            width: pillW,
            height: pillH
        )

        ctx.saveGState()
        defer { ctx.restoreGState() }

        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 14 * scaleFactor, cornerHeight: 14 * scaleFactor, transform: nil)
        ctx.addPath(pillPath)
        ctx.setFillColor(NSColor(calibratedWhite: 0.05, alpha: CGFloat(style.pillBackgroundOpacity)).cgColor)
        ctx.fillPath()

        // Find active word if word timestamps exist
        var displayString = fullText
        if let activeWord = caption.words.first(where: { currentTime >= $0.startTime && currentTime <= $0.endTime }) {
            displayString = fullText.replacingOccurrences(of: activeWord.word, with: "[\(activeWord.word)]")
        }

        drawSimpleText(
            displayString,
            in: ctx,
            rect: pillRect.insetBy(dx: padX * 0.6, dy: padY * 0.8),
            fontSize: fontSize,
            color: style.activeWordHighlightColor.nsColor,
            alignCenter: true
        )
    }

    // MARK: - CoreGraphics Text Drawing Helper

    private func drawSimpleText(
        _ text: String,
        in ctx: CGContext,
        rect: CGRect,
        fontSize: CGFloat,
        color: NSColor,
        alignCenter: Bool
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignCenter ? .center : .left
        paragraph.lineBreakMode = .byTruncatingTail

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(9, fontSize), weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])

        let drawX = alignCenter ? (rect.midX - bounds.width * 0.5) : rect.minX
        let drawY = rect.midY + bounds.height * 0.32

        ctx.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
        ctx.textPosition = CGPoint(x: drawX, y: drawY)
        CTLineDraw(line, ctx)
    }

    // MARK: - Decode Recorded Video Frames from Disk Bundle

    private func decodeVideoFrame(
        bundleURL: URL?,
        filename: String?,
        at time: TimeInterval,
        isWebcam: Bool
    ) -> CGImage? {
        guard let bundleURL, let filename else { return nil }
        let fileURL = bundleURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let generator: AVAssetImageGenerator
        if isWebcam {
            if cachedWebcamAssetURL != fileURL || webcamImageGenerator == nil {
                let asset = AVURLAsset(url: fileURL)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 30)
                gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 30)
                webcamImageGenerator = gen
                cachedWebcamAssetURL = fileURL
            }
            generator = webcamImageGenerator!
        } else {
            if cachedScreenAssetURL != fileURL || screenImageGenerator == nil {
                let asset = AVURLAsset(url: fileURL)
                let gen = AVAssetImageGenerator(asset: asset)
                gen.appliesPreferredTrackTransform = true
                gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
                gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
                screenImageGenerator = gen
                cachedScreenAssetURL = fileURL
            }
            generator = screenImageGenerator!
        }

        let cmTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
        return try? generator.copyCGImage(at: cmTime, actualTime: nil)
    }
}
