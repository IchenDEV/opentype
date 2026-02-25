import AppKit

enum AppIcon {

    @MainActor
    static func install() {
        NSApp.applicationIconImage = render(size: 512)
    }

    private static func render(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let ctx = NSGraphicsContext.current!.cgContext

            let inset = size * 0.1
            let iconRect = rect.insetBy(dx: inset, dy: inset)
            let cornerRadius = iconRect.width * 0.22

            // Drop shadow behind the rounded rect
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -size * 0.02),
                blur: size * 0.05,
                color: NSColor.black.withAlphaComponent(0.35).cgColor
            )
            let bgPath = CGPath(
                roundedRect: iconRect,
                cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                transform: nil
            )
            ctx.setFillColor(NSColor(red: 0.20, green: 0.50, blue: 0.98, alpha: 1).cgColor)
            ctx.addPath(bgPath)
            ctx.fillPath()
            ctx.restoreGState()

            // Gradient overlay for depth (lighter top → darker bottom)
            ctx.saveGState()
            ctx.addPath(bgPath)
            ctx.clip()
            let gradColors = [
                NSColor(white: 1.0, alpha: 0.18).cgColor,
                NSColor(white: 1.0, alpha: 0.0).cgColor,
                NSColor(white: 0.0, alpha: 0.10).cgColor,
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: gradColors as CFArray,
                locations: [0, 0.5, 1]
            )!
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: iconRect.midX, y: iconRect.maxY),
                end: CGPoint(x: iconRect.midX, y: iconRect.minY),
                options: []
            )
            ctx.restoreGState()

            // Waveform circle glyph — matches "waveform.circle.fill" from the About page
            let cx = iconRect.midX
            let cy = iconRect.midY
            let glyphR = iconRect.width * 0.30

            // Circle outline
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(iconRect.width * 0.025)
            ctx.addArc(center: CGPoint(x: cx, y: cy), radius: glyphR,
                       startAngle: 0, endAngle: .pi * 2, clockwise: false)
            ctx.strokePath()

            // Waveform bars inside the circle
            let barCount = 5
            let barWidth = iconRect.width * 0.032
            let barGap = iconRect.width * 0.045
            let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
            let startX = cx - totalW / 2

            let barHeights: [CGFloat] = [0.22, 0.38, 0.52, 0.38, 0.22]
            ctx.setFillColor(NSColor.white.cgColor)

            for i in 0..<barCount {
                let h = iconRect.width * barHeights[i]
                let x = startX + CGFloat(i) * (barWidth + barGap)
                let y = cy - h / 2
                let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
                let barPath = CGPath(
                    roundedRect: barRect,
                    cornerWidth: barWidth / 2, cornerHeight: barWidth / 2,
                    transform: nil
                )
                ctx.addPath(barPath)
                ctx.fillPath()
            }

            return true
        }
    }
}
