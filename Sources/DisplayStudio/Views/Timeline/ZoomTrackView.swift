import Foundation
import SwiftUI

public struct ZoomTrackView: View {
    @ObservedObject public var appState: AppState
    public let pixelsPerSecond: CGFloat
    public let totalWidth: CGFloat

    public init(appState: AppState, pixelsPerSecond: CGFloat, totalWidth: CGFloat) {
        self.appState = appState
        self.pixelsPerSecond = pixelsPerSecond
        self.totalWidth = totalWidth
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            // Track background
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.purple.opacity(0.08))
                .frame(width: totalWidth, height: 34)

            // Click & Keystroke activity ticks along the zoom track
            ForEach(appState.project.telemetry.clickEvents.filter { $0.phase == .down }) { click in
                Circle()
                    .fill(Color.cyan.opacity(0.65))
                    .frame(width: 5, height: 5)
                    .offset(x: CGFloat(click.timestamp) * pixelsPerSecond - 2.5, y: 11)
            }

            // Zoom Segment Blocks
            ForEach(Array(appState.project.zoomSegments.enumerated()), id: \.element.id) { index, segment in
                let isSelected = appState.selectedZoomSegmentID == segment.id
                let xOffset = CGFloat(segment.startTime) * pixelsPerSecond
                let segWidth = max(24, CGFloat(segment.duration) * pixelsPerSecond)

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: isSelected
                                    ? [Color.purple, Color(red: 0.58, green: 0.28, blue: 0.98)]
                                    : [Color.purple.opacity(0.75), Color.purple.opacity(0.52)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isSelected ? Color.white : Color.purple.opacity(0.9), lineWidth: isSelected ? 1.8 : 1.0)
                        )

                    HStack(spacing: 4) {
                        Image(systemName: segment.mode.isFollowCursor ? "cursorarrow.motionlines" : "scope")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%.1fx", segment.zoomDepth))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                }
                .frame(width: segWidth, height: 28)
                .offset(x: xOffset)
                .onTapGesture {
                    appState.selectedZoomSegmentID = segment.id
                    appState.selectedInspectorTab = .cursorZoom
                }
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { value in
                            let deltaSec = Double(value.translation.width / max(10, pixelsPerSecond))
                            let dur = segment.duration
                            let newStart = min(max(0, segment.startTime + deltaSec * 0.15), appState.project.telemetry.duration - dur)
                            if appState.project.zoomSegments.indices.contains(index) {
                                appState.project.zoomSegments[index].startTime = newStart
                                appState.project.zoomSegments[index].endTime = newStart + dur
                                appState.selectedZoomSegmentID = segment.id
                            }
                        }
                )
            }
        }
        .frame(width: totalWidth, height: 34, alignment: .leading)
    }
}
