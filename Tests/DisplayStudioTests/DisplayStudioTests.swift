import XCTest
@testable import DisplayStudio

final class DisplayStudioTests: XCTestCase {

    func testSpringPhysicsSolverAndCameraClamping() {
        let project = ProjectBundleManager.makeInteractiveDemoProject()
        let solver = SpringPhysicsSolver()
        solver.ensureBaked(for: project)

        // Evaluate inside first auto-zoom segment (around 1.8s)
        let zoomedState = solver.evaluate(atSourceTime: 1.8, in: project)
        XCTAssertGreaterThan(zoomedState.cameraZoom, 1.35, "Camera should zoom in during active ZoomSegment")
        XCTAssertTrue(
            (0.0...1.0).contains(zoomedState.smoothedCursorPos.x) &&
            (0.0...1.0).contains(zoomedState.smoothedCursorPos.y),
            "Smoothed cursor must remain inside normalized [0, 1] bounds"
        )

        // Evaluate click ripple around click timestamp 1.25s
        let clickState = solver.evaluate(atSourceTime: 1.32, in: project)
        XCTAssertFalse(clickState.activeRipples.isEmpty, "Click ripple should be active immediately after mouse down")
        XCTAssertLessThan(clickState.cursorClickScale, 0.99, "Cursor should bounce down during click")
    }

    func testAutoZoomGeneratorClustersClicksAndTyping() {
        let project = ProjectBundleManager.makeInteractiveDemoProject()
        let generated = AutoZoomGenerator.generateZoomSegments(from: project.telemetry)
        XCTAssertGreaterThanOrEqual(generated.count, 2, "AutoZoomGenerator should cluster clicks and typing into zoom segments")
        for seg in generated {
            XCTAssertGreaterThan(seg.endTime, seg.startTime)
            XCTAssertGreaterThan(seg.zoomDepth, 1.5)
        }
    }

    func testTimelineToSourceMappingWithSpeedRamps() {
        let project = ProjectBundleManager.makeInteractiveDemoProject()
        // At 7.2s, a 2.0x speed ramp is active in the demo project
        let mapped = project.mapTimelineToSourceTime(7.2)
        XCTAssertGreaterThan(mapped.speedMultiplier, 1.5, "Speed ramp should increase instantaneous playback rate")
    }

    func testMetalCompositorRendersCompositeFrame() {
        let project = ProjectBundleManager.makeInteractiveDemoProject()
        let solver = SpringPhysicsSolver()
        let state = solver.evaluate(atSourceTime: 4.8, in: project)
        let compositor = MetalCompositor()

        let image = compositor.renderCompositeFrame(
            project: project,
            frameState: state,
            canvasSize: CGSize(width: 1280, height: 720)
        )
        XCTAssertNotNil(image, "MetalCompositor should produce a non-nil CGImage")
        XCTAssertEqual(image?.width, 1280)
        XCTAssertEqual(image?.height, 720)
    }

    func testProjectBundleRoundTripPersistence() throws {
        let project = ProjectBundleManager.makeInteractiveDemoProject()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestBundle-\(UUID().uuidString).displaystudio", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try ProjectBundleManager.save(project: project, to: tempDir)
        let loaded = try ProjectBundleManager.load(from: tempDir)

        XCTAssertEqual(loaded.title, project.title)
        XCTAssertEqual(loaded.zoomSegments.count, project.zoomSegments.count)
        XCTAssertEqual(loaded.telemetry.clickEvents.count, project.telemetry.clickEvents.count)
    }
}
