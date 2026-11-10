import Foundation
import SwiftUI

public struct MultiTrackTimelineView: View {
    @ObservedObject public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        let pps = CGFloat(appState.timelineZoomScale)
        let duration = max(1.0, appState.project.totalTimelineDuration)
        let totalTrackWidth = max(680, CGFloat(duration) * pps)

        VStack(spacing: 0) {
            // Timeline Action Toolbar
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Button {
                        appState.splitClipAtPlayhead()
                    } label: {
                        Label("Split (⌘B)", systemImage: "scissors")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .keyboardShortcut("b", modifiers: [.command])
                    .controlSize(.small)

                    Button {
                        appState.deleteSelectedClip()
                    } label: {
                        Label("Delete Clip", systemImage: "trash")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .controlSize(.small)
                    .disabled(appState.project.clips.count <= 1)

                    Divider().frame(height: 14)

                    Button {
                        appState.addZoomSegmentAtPlayhead()
                    } label: {
                        Label("+ Zoom", systemImage: "plus.magnifyingglass")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .controlSize(.small)

                    Button {
                        appState.addSpeedRampAtPlayhead(multiplier: 2.0)
                    } label: {
                        Label("+ 2x Speed", systemImage: "bolt.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .controlSize(.small)

                    Button {
                        appState.addSpeedRampAtPlayhead(multiplier: 4.0)
                    } label: {
                        Label("+ 4x Speed", systemImage: "forward.fill")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .controlSize(.small)
                }

                Spacer()

                // Timeline Zoom Slider
                HStack(spacing: 6) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Slider(value: $appState.timelineZoomScale, in: 45...180)
                        .frame(width: 110)
                        .controlSize(.mini)
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(nsColor: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.17, alpha: 1.0)))

            Divider()

            // Track Headers + Scrollable Multi-Track Canvas
            HStack(spacing: 0) {
                // Left Fixed Track Headers
                VStack(alignment: .leading, spacing: 6) {
                    TrackHeaderRow(title: "Timecode", icon: "clock", height: 22, color: .secondary)
                    TrackHeaderRow(title: "Screen Clips", icon: "film", height: 34, color: .blue)
                    TrackHeaderRow(title: "Zoom Keyframes", icon: "plus.magnifyingglass", height: 34, color: .purple)
                    TrackHeaderRow(title: "Speed Ramps", icon: "bolt.fill", height: 26, color: .orange)
                    TrackHeaderRow(title: "Mic Audio", icon: "mic.fill", height: 28, color: .green)
                    TrackHeaderRow(title: "System Audio", icon: "speaker.wave.2.fill", height: 28, color: .cyan)
                    TrackHeaderRow(title: "Captions", icon: "captions.bubble.fill", height: 26, color: .yellow)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(width: 138, alignment: .leading)
                .background(Color(nsColor: NSColor(srgbRed: 0.09, green: 0.10, blue: 0.14, alpha: 1.0)))

                Divider()

                // Scrollable Timeline Tracks + Scrubber Playhead
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            // 1. Time Ruler
                            TimelineRulerView(duration: duration, pixelsPerSecond: pps, totalWidth: totalTrackWidth)

                            // 2. Video Clips Track
                            ClipsTrackRowView(appState: appState, pixelsPerSecond: pps, totalWidth: totalTrackWidth)

                            // 3. Zoom Keyframes Track
                            ZoomTrackView(appState: appState, pixelsPerSecond: pps, totalWidth: totalTrackWidth)

                            // 4. Speed Ramps Track
                            SpeedRampTrackRowView(appState: appState, pixelsPerSecond: pps, totalWidth: totalTrackWidth)

                            // 5. Microphone Waveform Track
                            WaveformTrackView(
                                samples: appState.project.audioSettings.micWaveformSamples,
                                tintColor: .green,
                                isMuted: appState.project.audioSettings.isMicMuted,
                                gain: appState.project.audioSettings.micVolume,
                                totalWidth: totalTrackWidth
                            )

                            // 6. System Audio Waveform Track
                            WaveformTrackView(
                                samples: appState.project.audioSettings.sysWaveformSamples,
                                tintColor: .cyan,
                                isMuted: appState.project.audioSettings.isSystemMuted,
                                gain: appState.project.audioSettings.systemVolume,
                                totalWidth: totalTrackWidth
                            )

                            // 7. Auto-Captions Track
                            CaptionsTrackRowView(appState: appState, pixelsPerSecond: pps, totalWidth: totalTrackWidth)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let localX = max(0, drag.location.x - 12)
                                    let newTime = Double(localX / max(10, pps))
                                    appState.seek(to: newTime)
                                }
                        )

                        // Red Playhead Line + Cap
                        let playheadX = 12 + CGFloat(appState.playheadTime) * pps
                        VStack(spacing: 0) {
                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                            Rectangle()
                                .fill(Color.red)
                                .frame(width: 2, height: 224)
                        }
                        .offset(x: playheadX - 5.5, y: 2)
                        .allowsHitTesting(false)
                    }
                }
                .background(Color(nsColor: NSColor(srgbRed: 0.07, green: 0.08, blue: 0.11, alpha: 1.0)))
            }
        }
        .frame(height: 272)
    }
}

// MARK: - Sub-Tracks

private struct TrackHeaderRow: View {
    let title: String
    let icon: String
    let height: CGFloat
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: height, alignment: .leading)
    }
}

private struct TimelineRulerView: View {
    let duration: TimeInterval
    let pixelsPerSecond: CGFloat
    let totalWidth: CGFloat

    var body: some View {
        let totalSeconds = Int(ceil(duration))
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.white.opacity(0.03))
                .frame(width: totalWidth, height: 22)

            ForEach(0...totalSeconds, id: \.self) { sec in
                let x = CGFloat(sec) * pixelsPerSecond
                HStack(spacing: 3) {
                    Rectangle()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 1, height: 10)
                    Text(String(format: "%02d:%02d", sec / 60, sec % 60))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .offset(x: x)
            }
        }
        .frame(width: totalWidth, height: 22, alignment: .leading)
    }
}

private struct ClipsTrackRowView: View {
    @ObservedObject var appState: AppState
    let pixelsPerSecond: CGFloat
    let totalWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.08))
                .frame(width: totalWidth, height: 34)

            HStack(spacing: 2) {
                ForEach(appState.project.clips) { clip in
                    let isSelected = appState.selectedClipID == clip.id
                    let clipW = max(28, CGFloat(clip.timelineDuration) * pixelsPerSecond - 2)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: isSelected
                                        ? [Color.blue.opacity(0.85), Color.blue.opacity(0.62)]
                                        : [Color.blue.opacity(0.48), Color.blue.opacity(0.32)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Color.white : Color.blue.opacity(0.75), lineWidth: isSelected ? 1.5 : 1)
                            )

                        HStack(spacing: 6) {
                            Image(systemName: "film")
                                .font(.system(size: 10, weight: .semibold))
                            Text(clip.label)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1fs", clip.timelineDuration))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                    }
                    .frame(width: clipW, height: 30)
                    .onTapGesture {
                        appState.selectedClipID = clip.id
                    }
                }
            }
        }
        .frame(width: totalWidth, height: 34, alignment: .leading)
    }
}

private struct SpeedRampTrackRowView: View {
    @ObservedObject var appState: AppState
    let pixelsPerSecond: CGFloat
    let totalWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(0.07))
                .frame(width: totalWidth, height: 26)

            ForEach(appState.project.speedRampSegments) { ramp in
                let isSelected = appState.selectedSpeedRampID == ramp.id
                let x = CGFloat(ramp.startTime) * pixelsPerSecond
                let w = max(24, CGFloat(ramp.endTime - ramp.startTime) * pixelsPerSecond)

                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9))
                    Text(String(format: "%.1fx", ramp.speedMultiplier))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Spacer()
                    Button {
                        appState.selectedSpeedRampID = ramp.id
                        appState.deleteSelectedSpeedRamp()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(width: w, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.orange.opacity(isSelected ? 0.9 : 0.72))
                )
                .offset(x: x)
                .onTapGesture {
                    appState.selectedSpeedRampID = ramp.id
                }
            }
        }
        .frame(width: totalWidth, height: 26, alignment: .leading)
    }
}

private struct CaptionsTrackRowView: View {
    @ObservedObject var appState: AppState
    let pixelsPerSecond: CGFloat
    let totalWidth: CGFloat

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.yellow.opacity(0.06))
                .frame(width: totalWidth, height: 26)

            ForEach(appState.project.captionSegments) { cap in
                let x = CGFloat(cap.startTime) * pixelsPerSecond
                let w = max(32, CGFloat(cap.endTime - cap.startTime) * pixelsPerSecond)

                HStack(spacing: 4) {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 9))
                    Text(cap.text)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .frame(width: w, height: 20, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.yellow.opacity(0.85))
                )
                .offset(x: x)
                .onTapGesture {
                    appState.selectedCaptionID = cap.id
                    appState.selectedInspectorTab = .captionsKeys
                }
            }
        }
        .frame(width: totalWidth, height: 26, alignment: .leading)
    }
}
