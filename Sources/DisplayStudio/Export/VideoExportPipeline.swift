import Foundation
import AVFoundation
import CoreVideo
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@MainActor
public final class VideoExportPipeline: ObservableObject {
    @Published public private(set) var isExporting: Bool = false
    @Published public private(set) var progress: Double = 0.0
    @Published public private(set) var currentFrameIndex: Int = 0
    @Published public private(set) var totalFrames: Int = 0
    @Published public private(set) var renderedFPS: Double = 0.0
    @Published public private(set) var statusText: String = "Ready to export"
    @Published public private(set) var lastExportedURL: URL?
    @Published public private(set) var errorMessage: String?

    private var isCancelled: Bool = false

    public init() {}

    public func cancelExport() {
        isCancelled = true
        statusText = "Cancelling export…"
    }

    public func exportProject(
        _ project: StudioProject,
        bundleURL: URL?,
        destinationURL: URL
    ) async throws -> URL {
        isExporting = true
        isCancelled = false
        progress = 0.0
        errorMessage = nil
        lastExportedURL = nil

        let settings = project.exportSettings
        let canvasSize = project.aspectRatio.canvasSize(
            for: project.telemetry.sourceSize,
            baseHeight: settings.resolution.baseHeight
        )
        let width = max(320, Int(canvasSize.width) & ~1)
        let height = max(320, Int(canvasSize.height) & ~1)
        let fps = max(12, settings.format == .gif ? min(24, settings.fps) : settings.fps)
        let totalDuration = max(0.5, project.totalTimelineDuration)
        let frameCount = max(2, Int(ceil(totalDuration * Double(fps))))

        self.totalFrames = frameCount
        self.currentFrameIndex = 0
        self.statusText = "Rendering \(width)×\(height) @ \(fps)fps (\(settings.format.rawValue))…"

        defer {
            isExporting = false
        }

        do {
            let finalURL: URL
            switch settings.format {
            case .gif:
                finalURL = try await exportAnimatedGIF(
                    project: project,
                    bundleURL: bundleURL,
                    destinationURL: destinationURL,
                    size: CGSize(width: width / 2, height: height / 2),
                    fps: fps,
                    totalFrames: frameCount
                )
            case .webM:
                finalURL = try await exportWebMOrMP4(
                    project: project,
                    bundleURL: bundleURL,
                    destinationURL: destinationURL,
                    size: CGSize(width: width, height: height),
                    fps: fps,
                    totalFrames: frameCount
                )
            case .mp4H264, .mp4HEVC:
                finalURL = try await exportMP4Video(
                    project: project,
                    bundleURL: bundleURL,
                    destinationURL: destinationURL,
                    size: CGSize(width: width, height: height),
                    fps: fps,
                    totalFrames: frameCount,
                    useHEVC: settings.format == .mp4HEVC
                )
            }

            self.lastExportedURL = finalURL
            self.progress = 1.0
            self.statusText = "Export complete: \(finalURL.lastPathComponent)"
            return finalURL
        } catch {
            self.errorMessage = error.localizedDescription
            self.statusText = "Export failed"
            throw error
        }
    }

    // MARK: - Hardware-Accelerated MP4 / HEVC Export

    private func exportMP4Video(
        project: StudioProject,
        bundleURL: URL?,
        destinationURL: URL,
        size: CGSize,
        fps: Int,
        totalFrames: Int,
        useHEVC: Bool
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: destinationURL)
        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mp4)

        let width = Int(size.width)
        let height = Int(size.height)
        let bitrate = Int(Double(width * height * fps) * project.exportSettings.quality.bitsPerPixel)

        let codec: AVVideoCodecType = useHEVC ? .hevc : .h264
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(1_500_000, bitrate),
                AVVideoExpectedSourceFrameRateKey: fps
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttrs
        )

        guard writer.canAdd(writerInput) else {
            throw NSError(domain: "DisplayStudio.Export", code: -10, userInfo: [NSLocalizedDescriptionKey: "Cannot add video input to AVAssetWriter"])
        }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let solver = SpringPhysicsSolver()
        solver.ensureBaked(for: project)
        let compositor = MetalCompositor()
        let startWallTime = ProcessInfo.processInfo.systemUptime

        for frameIdx in 0..<totalFrames {
            if isCancelled {
                writer.cancelWriting()
                throw NSError(domain: "DisplayStudio.Export", code: -99, userInfo: [NSLocalizedDescriptionKey: "Export cancelled by user"])
            }

            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }

            let timelineTime = Double(frameIdx) / Double(fps)
            let mapped = project.mapTimelineToSourceTime(timelineTime)
            let frameState = solver.evaluate(atSourceTime: mapped.sourceTime, in: project)

            guard let pool = adaptor.pixelBufferPool else { continue }
            var pixelBufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)

            if let pixelBuffer = pixelBufferOut {
                compositor.renderToPixelBuffer(
                    pixelBuffer,
                    project: project,
                    frameState: frameState,
                    bundleURL: bundleURL
                )
                let presentationTime = CMTime(value: CMTimeValue(frameIdx), timescale: CMTimeScale(fps))
                adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            }

            if frameIdx % 3 == 0 || frameIdx == totalFrames - 1 {
                let elapsed = max(0.01, ProcessInfo.processInfo.systemUptime - startWallTime)
                self.currentFrameIndex = frameIdx + 1
                self.progress = Double(frameIdx + 1) / Double(totalFrames)
                self.renderedFPS = Double(frameIdx + 1) / elapsed
                await Task.yield()
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if let err = writer.error {
            throw err
        }
        return destinationURL
    }

    // MARK: - High-Quality Animated GIF Export

    private func exportAnimatedGIF(
        project: StudioProject,
        bundleURL: URL?,
        destinationURL: URL,
        size: CGSize,
        fps: Int,
        totalFrames: Int
    ) async throws -> URL {
        try? FileManager.default.removeItem(at: destinationURL)
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.gif.identifier as CFString,
            totalFrames,
            nil
        ) else {
            throw NSError(domain: "DisplayStudio.Export", code: -20, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize GIF destination"])
        }

        let fileProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFLoopCount as String: 0
            ]
        ]
        CGImageDestinationSetProperties(destination, fileProps as CFDictionary)

        let frameDelay = 1.0 / Double(fps)
        let frameProps: [String: Any] = [
            kCGImagePropertyGIFDictionary as String: [
                kCGImagePropertyGIFDelayTime as String: frameDelay,
                kCGImagePropertyGIFUnclampedDelayTime as String: frameDelay
            ]
        ]

        let solver = SpringPhysicsSolver()
        solver.ensureBaked(for: project)
        let compositor = MetalCompositor()
        let startWallTime = ProcessInfo.processInfo.systemUptime

        for frameIdx in 0..<totalFrames {
            if isCancelled {
                throw NSError(domain: "DisplayStudio.Export", code: -99, userInfo: [NSLocalizedDescriptionKey: "Export cancelled"])
            }
            let timelineTime = Double(frameIdx) / Double(fps)
            let mapped = project.mapTimelineToSourceTime(timelineTime)
            let frameState = solver.evaluate(atSourceTime: mapped.sourceTime, in: project)

            if let cgImage = compositor.renderCompositeFrame(
                project: project,
                frameState: frameState,
                canvasSize: size,
                bundleURL: bundleURL
            ) {
                CGImageDestinationAddImage(destination, cgImage, frameProps as CFDictionary)
            }

            if frameIdx % 2 == 0 || frameIdx == totalFrames - 1 {
                let elapsed = max(0.01, ProcessInfo.processInfo.systemUptime - startWallTime)
                self.currentFrameIndex = frameIdx + 1
                self.progress = Double(frameIdx + 1) / Double(totalFrames)
                self.renderedFPS = Double(frameIdx + 1) / elapsed
                await Task.yield()
            }
        }

        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "DisplayStudio.Export", code: -21, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize GIF file"])
        }
        return destinationURL
    }

    // MARK: - WebM Export (via FFmpeg if installed, or MP4 fallback)

    private func exportWebMOrMP4(
        project: StudioProject,
        bundleURL: URL?,
        destinationURL: URL,
        size: CGSize,
        fps: Int,
        totalFrames: Int
    ) async throws -> URL {
        let tempMP4 = FileManager.default.temporaryDirectory.appendingPathComponent("displaystudio_temp_\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: tempMP4) }

        _ = try await exportMP4Video(
            project: project,
            bundleURL: bundleURL,
            destinationURL: tempMP4,
            size: size,
            fps: fps,
            totalFrames: totalFrames,
            useHEVC: false
        )

        let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        if let ffmpegExec = ffmpegPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            statusText = "Transcoding VP9 WebM container…"
            try? FileManager.default.removeItem(at: destinationURL)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ffmpegExec)
            proc.arguments = [
                "-y", "-i", tempMP4.path,
                "-c:v", "libvpx-vp9", "-b:v", "4M",
                destinationURL.path
            ]
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0, FileManager.default.fileExists(atPath: destinationURL.path) {
                return destinationURL
            }
        }

        // Copy high-compatibility H.264 stream to destination if ffmpeg is not installed
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.copyItem(at: tempMP4, to: destinationURL)
        return destinationURL
    }
}
