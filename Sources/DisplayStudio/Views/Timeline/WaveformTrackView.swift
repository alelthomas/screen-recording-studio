import Foundation
import SwiftUI

public struct WaveformTrackView: View {
    public let samples: [Float]
    public let tintColor: Color
    public let isMuted: Bool
    public let gain: Double
    public let totalWidth: CGFloat

    public init(
        samples: [Float],
        tintColor: Color,
        isMuted: Bool,
        gain: Double,
        totalWidth: CGFloat
    ) {
        self.samples = samples
        self.tintColor = tintColor
        self.isMuted = isMuted
        self.gain = gain
        self.totalWidth = totalWidth
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(tintColor.opacity(0.08))
                .frame(width: totalWidth, height: 28)

            Canvas { context, size in
                guard !samples.isEmpty else { return }
                let count = samples.count
                let barSpacing: CGFloat = max(2.0, size.width / CGFloat(count))
                let barWidth: CGFloat = max(1.5, barSpacing * 0.62)
                let midY = size.height * 0.5
                let effectiveGain = isMuted ? 0.08 : CGFloat(min(1.8, max(0.1, gain)))

                for (idx, sample) in samples.enumerated() {
                    let x = CGFloat(idx) * barSpacing
                    let amp = min(size.height * 0.9, max(2.0, CGFloat(sample) * size.height * 0.85 * effectiveGain))
                    let rect = CGRect(x: x, y: midY - amp * 0.5, width: barWidth, height: amp)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth * 0.5)
                    context.fill(path, with: .color(isMuted ? .gray.opacity(0.35) : tintColor.opacity(0.85)))
                }
            }
            .frame(width: totalWidth, height: 28)
        }
        .frame(width: totalWidth, height: 28)
    }
}
