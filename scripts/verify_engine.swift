import Foundation
import CoreGraphics
import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main
struct VerifyEngineRunner {
    @MainActor
    static func main() async throws {
        print("1. Creating Interactive Demo StudioProject...")
        var project = ProjectBundleManager.makeInteractiveDemoProject()
        assert(project.zoomSegments.count == 3, "Expected 3 default auto-zoom segments")
        assert(project.telemetry.cursorSamples.count > 1000, "Expected 120Hz cursor samples")

        print("2. Verifying SpringPhysicsSolver trajectory & zoom camera clamping...")
        let solver = SpringPhysicsSolver()
        solver.ensureBaked(for: project)

        let stateAtClick = solver.evaluate(atSourceTime: 1.30, in: project)
        assert(stateAtClick.cameraZoom > 1.25, "Expected camera zoom > 1.25x during first zoom segment")
        assert(!stateAtClick.activeRipples.isEmpty, "Expected active click ripple at t=1.30s")
        print("   -> t=1.30s: cameraZoom=\(String(format: "%.2fx", stateAtClick.cameraZoom)), ripples=\(stateAtClick.activeRipples.count), clickScale=\(String(format: "%.2f", stateAtClick.cursorClickScale))")

        print("3. Verifying AutoZoomGenerator click & typing clustering...")
        let generatedZooms = AutoZoomGenerator.generateZoomSegments(from: project.telemetry)
        assert(generatedZooms.count >= 2, "Expected >= 2 clustered zoom segments")
        print("   -> Generated \(generatedZooms.count) auto-zoom segments")

        print("4. Verifying MetalCompositor across wallpapers, aspect ratios, and zoom states...")
        let compositor = MetalCompositor()
        let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // Render Frame A: 16:9 Wide, Sequoia Sunrise wallpaper, zoomed in on search bar typing burst + keystroke pill + caption
        let stateTyping = solver.evaluate(atSourceTime: 4.85, in: project)
        if let imgA = compositor.renderCompositeFrame(
            project: project,
            frameState: stateTyping,
            canvasSize: CGSize(width: 1920, height: 1080)
        ) {
            let urlA = outDir.appendingPathComponent("preview_zoom_typing_16x9.png")
            savePNG(imgA, to: urlA)
            print("   -> Saved \(urlA.path) (\(imgA.width)x\(imgA.height))")
        } else {
            fatalError("Failed to render Frame A")
        }

        // Render Frame B: Cyber Aurora wallpaper, click ripple at export button (t=8.30s)
        project.background.wallpaperPreset = .cyberAurora
        project.webcamSettings.shape = .circle
        project.webcamSettings.corner = .bottomLeft
        let stateExportClick = solver.evaluate(atSourceTime: 8.30, in: project)
        if let imgB = compositor.renderCompositeFrame(
            project: project,
            frameState: stateExportClick,
            canvasSize: CGSize(width: 1920, height: 1080)
        ) {
            let urlB = outDir.appendingPathComponent("preview_click_ripple_aurora.png")
            savePNG(imgB, to: urlB)
            print("   -> Saved \(urlB.path) (\(imgB.width)x\(imgB.height))")
        } else {
            fatalError("Failed to render Frame B")
        }

        print("5. Rendering StudioMainWindow UI snapshot via NSHostingView...")
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .darkAqua)
        let appState = AppState()
        appState.seek(to: 4.85)
        appState.selectedInspectorTab = .cursorZoom
        let frameRect = NSRect(x: 0, y: 0, width: 1360, height: 840)
        let window = NSWindow(
            contentRect: frameRect,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        let hostingView = NSHostingView(
            rootView: StudioMainWindow(appState: appState)
                .frame(width: 1360, height: 840)
                .environment(\.colorScheme, .dark)
        )
        hostingView.frame = frameRect
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        try? await Task.sleep(nanoseconds: 150_000_000)

        if let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) {
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
            if let uiCGImage = bitmapRep.cgImage {
                let uiURL = outDir.appendingPathComponent("studio_main_window_ui.png")
                savePNG(uiCGImage, to: uiURL)
                print("   -> Saved Studio UI snapshot at \(uiURL.path) (\(uiCGImage.width)x\(uiCGImage.height))")
            }
        }

        print("6. Verifying .displaystudio Project Bundle round-trip persistence...")
        let bundleURL = outDir.appendingPathComponent("VerifyTest.displaystudio", isDirectory: true)
        try ProjectBundleManager.save(project: project, to: bundleURL)
        let loaded = try ProjectBundleManager.load(from: bundleURL)
        assert(loaded.title == project.title, "Bundle title mismatch")
        try? FileManager.default.removeItem(at: bundleURL)
        print("   -> .displaystudio bundle round-trip verified")

        print("7. Verifying VideoExportPipeline MP4 & GIF export...")
        let pipeline = VideoExportPipeline()
        var quickProject = project
        quickProject.clips = [
            ClipSegment(label: "Short Test", sourceStartTime: 0.8, sourceEndTime: 2.3, speedMultiplier: 1.0)
        ]
        quickProject.exportSettings.resolution = .p720
        quickProject.exportSettings.fps = 24
        quickProject.exportSettings.format = .mp4HEVC

        let mp4URL = outDir.appendingPathComponent("test_export.mp4")
        _ = try await pipeline.exportProject(quickProject, bundleURL: nil, destinationURL: mp4URL)
        let mp4Attrs = try FileManager.default.attributesOfItem(atPath: mp4URL.path)
        let mp4Size = (mp4Attrs[.size] as? Int) ?? 0
        assert(mp4Size > 1024, "Expected exported MP4 size > 1KB")
        print("   -> Exported MP4 (\(mp4Size) bytes) at \(mp4URL.path)")

        quickProject.exportSettings.format = .gif
        let gifURL = outDir.appendingPathComponent("test_export.gif")
        _ = try await pipeline.exportProject(quickProject, bundleURL: nil, destinationURL: gifURL)
        let gifAttrs = try FileManager.default.attributesOfItem(atPath: gifURL.path)
        let gifSize = (gifAttrs[.size] as? Int) ?? 0
        assert(gifSize > 1024, "Expected exported GIF size > 1KB")
        print("   -> Exported Animated GIF (\(gifSize) bytes) at \(gifURL.path)")

        print("ALL DISPLAY STUDIO ENGINE, UI & EXPORT TESTS PASSED!")
    }

    static func savePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
