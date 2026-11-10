import Foundation
import SwiftUI
import AppKit

public struct PreviewCanvasView: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Status & Telemetry Pill Bar above Canvas
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "aspectratio")
                        .foregroundStyle(.secondary)
                    Text(appState.project.aspectRatio.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06), in: Capsule())

                HStack(spacing: 6) {
                    Image(systemName: "plus.magnifyingglass")
                        .foregroundStyle(.purple)
                    Text(String(format: "Camera %.2fx", appState.currentFrameState.cameraZoom))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.16), in: Capsule())

                let mapped = appState.project.mapTimelineToSourceTime(appState.playheadTime)
                if abs(mapped.speedMultiplier - 1.0) > 0.05 {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.orange)
                        Text(String(format: "%.1fx Speed", mapped.speedMultiplier))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("Spring:")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(appState.project.cursorSettings.springPreset.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.cyan.opacity(0.12), in: Capsule())
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color(nsColor: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1.0)))

            // Main Interactive Stage
            GeometryReader { geo in
                ZStack {
                    Color(nsColor: NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1.0))

                    if let cgImage = appState.currentPreviewImage {
                        let imgAspect = CGFloat(cgImage.width) / CGFloat(max(1, cgImage.height))
                        let availW = max(120, geo.size.width - 36)
                        let availH = max(120, geo.size.height - 24)
                        let fitSize: CGSize = {
                            if availW / availH > imgAspect {
                                let h = availH * CGFloat(appState.canvasZoomMode)
                                return CGSize(width: h * imgAspect, height: h)
                            } else {
                                let w = availW * CGFloat(appState.canvasZoomMode)
                                return CGSize(width: w, height: w / imgAspect)
                            }
                        }()

                        ZStack {
                            Image(decorative: cgImage, scale: 1.0)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: fitSize.width, height: fitSize.height)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.55), radius: 20, y: 8)

                            // Interactive Fixed-Zoom Target Reticle Overlay (when selected ZoomSegment is in Fixed Point mode)
                            if let zoomID = appState.selectedZoomSegmentID,
                               let zoomIdx = appState.project.zoomSegments.firstIndex(where: { $0.id == zoomID }),
                               case .fixedPoint(let fixedPt) = appState.project.zoomSegments[zoomIdx].mode {
                                let screenRect = MetalCompositor.computeScreenFrameRect(
                                    canvasSize: fitSize,
                                    sourceSize: appState.project.telemetry.sourceSize,
                                    paddingRatio: appState.project.frameStyling.paddingRatio
                                )
                                let reticleX = screenRect.minX + fixedPt.x * screenRect.width
                                let reticleY = screenRect.minY + fixedPt.y * screenRect.height

                                FixedZoomReticleOverlay(point: CGPoint(x: reticleX, y: reticleY))
                                    .frame(width: fitSize.width, height: fitSize.height)
                                    .gesture(
                                        DragGesture(minimumDistance: 1)
                                            .onChanged { drag in
                                                let normX = min(0.95, max(0.05, (drag.location.x - screenRect.minX) / max(1, screenRect.width)))
                                                let normY = min(0.95, max(0.05, (drag.location.y - screenRect.minY) / max(1, screenRect.height)))
                                                appState.project.zoomSegments[zoomIdx].mode = .fixedPoint(CGPoint(x: normX, y: normY))
                                            }
                                    )
                            }
                        }
                    }
                }
            }

            // Bottom Transport Control Bar
            HStack(spacing: 16) {
                HStack(spacing: 10) {
                    Button {
                        appState.seek(to: 0)
                    } label: {
                        Image(systemName: "backward.end.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Jump to Start")

                    Button {
                        appState.togglePlayback()
                    } label: {
                        Image(systemName: appState.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .help("Play / Pause (Space)")

                    Button {
                        appState.seek(to: appState.project.totalTimelineDuration)
                    } label: {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Jump to End")
                }

                // Timecode Display
                Text("\(formatTimecode(appState.playheadTime)) / \(formatTimecode(appState.project.totalTimelineDuration))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                Spacer()

                // Quick Studio Actions on Transport Bar
                HStack(spacing: 8) {
                    Button {
                        appState.addZoomSegmentAtPlayhead()
                    } label: {
                        Label("Add Zoom", systemImage: "plus.magnifyingglass")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .controlSize(.small)
                    .tint(.purple)

                    Button {
                        appState.splitClipAtPlayhead()
                    } label: {
                        Label("Split Clip", systemImage: "scissors")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .controlSize(.small)

                    Button {
                        appState.addSpeedRampAtPlayhead(multiplier: 2.0)
                    } label: {
                        Label("2x Speed Ramp", systemImage: "bolt.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(nsColor: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.14, alpha: 1.0)))
        }
    }

    private func formatTimecode(_ time: TimeInterval) -> String {
        let mins = Int(time) / 60
        let secs = Int(time) % 60
        let hundredths = Int((time - floor(time)) * 100)
        return String(format: "%02d:%02d.%02d", mins, secs, hundredths)
    }
}

private struct FixedZoomReticleOverlay: View {
    let point: CGPoint

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.purple, lineWidth: 2)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.purple.opacity(0.18)))
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
            Text("FIXED ZOOM TARGET (DRAG)")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple, in: Capsule())
                .offset(y: -26)
        }
        .position(point)
    }
}
