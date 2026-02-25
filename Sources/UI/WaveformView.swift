import SwiftUI

struct WaveformView: View {
    let level: Float

    private let barCount = 5
    @State private var smoothLevel: Float = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            Canvas { context, size in
                let barWidth: CGFloat = 2.5
                let gap: CGFloat = 2
                let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * gap
                let originX = (size.width - totalW) / 2
                let time = timeline.date.timeIntervalSinceReferenceDate

                // Smooth the level to avoid jitter
                let target = CGFloat(max(level, 0.05))
                let smooth = target * 0.4 + CGFloat(smoothLevel) * 0.6

                for i in 0..<barCount {
                    let phase = Double(i) / Double(barCount) * .pi * 2
                    let wave = (sin(time * 6 + phase) + 1) / 2
                    let barH = max(3, smooth * size.height * 0.9 * wave + 2)

                    let x = originX + CGFloat(i) * (barWidth + gap)
                    let y = (size.height - barH) / 2
                    let rect = CGRect(x: x, y: y, width: barWidth, height: barH)
                    let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)

                    let opacity = 0.5 + smooth * 0.5
                    context.fill(path, with: .color(.red.opacity(opacity)))
                }
            }
        }
        .onChange(of: level) { _, newVal in
            smoothLevel = smoothLevel * 0.6 + newVal * 0.4
        }
    }
}
