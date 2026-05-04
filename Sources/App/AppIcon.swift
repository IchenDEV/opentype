import AppKit

enum AppIcon {
    enum Mode {
        case light
        case dark
    }

    @MainActor
    static func install() {
        NSApp.applicationIconImage = image(size: 512)
    }

    @MainActor
    static func image(size: CGFloat) -> NSImage {
        let mode = preferredMode
        return bundledIcon(for: mode, size: size) ?? render(size: size, mode: mode)
    }

    static func render(size: CGFloat, mode: Mode) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            drawIcon(in: rect, context: context, mode: mode)
            return true
        }
        image.isTemplate = false
        return image
    }

    @MainActor
    private static var preferredMode: Mode {
        switch AppSettings.shared.appIconAppearance {
        case .system: return currentMode
        case .light: return .light
        case .dark: return .dark
        }
    }

    @MainActor
    private static var currentMode: Mode {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua ? .dark : .light
    }

    private static func bundledIcon(for mode: Mode, size: CGFloat) -> NSImage? {
        let resource = mode == .dark ? "AppIconDark" : "AppIconLight"
        guard let url = Bundle.main.url(forResource: resource, withExtension: "icns")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
            let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = false
        return image
    }

    private static func drawIcon(in rect: CGRect, context: CGContext, mode: Mode) {
        let palette = Palette(mode: mode)
        let layout = iconLayout(in: rect)
        let basePath = CGPath(
            roundedRect: layout.baseRect,
            cornerWidth: layout.baseRect.width * 0.235,
            cornerHeight: layout.baseRect.height * 0.235,
            transform: nil
        )

        context.clear(rect)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        drawBase(basePath, in: layout.baseRect, context: context, palette: palette, side: layout.side)
        drawMicrophone(in: layout.contentRect, context: context, palette: palette)
        drawWaveTile(in: layout.contentRect, context: context, palette: palette)
    }

    private static func iconLayout(in rect: CGRect) -> (side: CGFloat, baseRect: CGRect, contentRect: CGRect) {
        let side = min(rect.width, rect.height)
        let baseRect = rect.insetBy(dx: side * 0.08, dy: side * 0.08)
        let contentRect = baseRect.insetBy(dx: baseRect.width * 0.10, dy: baseRect.height * 0.10)
        return (side, baseRect, contentRect)
    }

    private static func drawBase(
        _ path: CGPath,
        in rect: CGRect,
        context: CGContext,
        palette: Palette,
        side: CGFloat
    ) {
        context.saveGState()
        context.addPath(path)
        context.clip()
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [palette.baseTop.cgColor, palette.baseBottom.cgColor] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.maxY),
            end: CGPoint(x: rect.midX, y: rect.minY),
            options: []
        )
        context.restoreGState()

        context.setStrokeColor(palette.baseStroke.cgColor)
        context.setLineWidth(side * 0.011)
        context.addPath(path)
        context.strokePath()
    }

    private static func drawMicrophone(in rect: CGRect, context: CGContext, palette: Palette) {
        let width = rect.width
        let centerX = rect.midX
        let topY = rect.minY + width * 0.49
        let bottomY = rect.minY + width * 0.255
        let leftX = centerX - width * 0.31
        let rightX = centerX + width * 0.31

        let cup = CGMutablePath()
        cup.move(to: CGPoint(x: leftX, y: topY))
        cup.addCurve(
            to: CGPoint(x: centerX, y: bottomY),
            control1: CGPoint(x: leftX, y: rect.minY + width * 0.34),
            control2: CGPoint(x: centerX - width * 0.2, y: bottomY)
        )
        cup.addCurve(
            to: CGPoint(x: rightX, y: topY),
            control1: CGPoint(x: centerX + width * 0.2, y: bottomY),
            control2: CGPoint(x: rightX, y: rect.minY + width * 0.34)
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -width * 0.012),
            blur: width * 0.028,
            color: palette.symbolShadow.cgColor
        )
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(width * 0.07)
        context.setStrokeColor(palette.micStroke.cgColor)
        context.addPath(cup)
        context.strokePath()

        context.setLineWidth(width * 0.055)
        context.move(to: CGPoint(x: centerX, y: bottomY))
        context.addLine(to: CGPoint(x: centerX, y: rect.minY + width * 0.16))
        context.strokePath()
        context.restoreGState()

        let base = CGRect(
            x: centerX - width * 0.105,
            y: rect.minY + width * 0.115,
            width: width * 0.21,
            height: width * 0.06
        )
        context.setFillColor(palette.micStroke.cgColor)
        context.addPath(CGPath(roundedRect: base, cornerWidth: base.height / 2, cornerHeight: base.height / 2, transform: nil))
        context.fillPath()
    }

    private static func drawWaveTile(in rect: CGRect, context: CGContext, palette: Palette) {
        let width = rect.width
        let tileSide = width * 0.43
        let tile = CGRect(
            x: rect.midX - tileSide / 2,
            y: rect.minY + width * 0.365,
            width: tileSide,
            height: tileSide
        )
        let tilePath = CGPath(
            roundedRect: tile,
            cornerWidth: tileSide * 0.22,
            cornerHeight: tileSide * 0.22,
            transform: nil
        )

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -width * 0.025),
            blur: width * 0.05,
            color: palette.tileShadow.cgColor
        )
        context.setFillColor(palette.tileBottom.cgColor)
        context.addPath(tilePath)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(tilePath)
        context.clip()
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [palette.tileTop.cgColor, palette.tileBottom.cgColor] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: tile.minX, y: tile.maxY),
            end: CGPoint(x: tile.maxX, y: tile.minY),
            options: []
        )
        context.restoreGState()

        context.setStrokeColor(palette.tileStroke.cgColor)
        context.setLineWidth(width * 0.008)
        context.addPath(tilePath)
        context.strokePath()

        let barWidth = tile.width * 0.08
        let gap = tile.width * 0.085
        let heights = [0.31, 0.5, 0.76, 0.5, 0.31].map { tile.height * $0 }
        let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
        let startX = tile.midX - totalWidth / 2

        context.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        for (index, height) in heights.enumerated() {
            let bar = CGRect(
                x: startX + CGFloat(index) * (barWidth + gap),
                y: tile.midY - height / 2,
                width: barWidth,
                height: height
            )
            context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
            context.fillPath()
        }
    }
}

private struct Palette {
    let baseTop: NSColor
    let baseBottom: NSColor
    let baseStroke: NSColor
    let micStroke: NSColor
    let symbolShadow: NSColor
    let tileTop: NSColor
    let tileBottom: NSColor
    let tileStroke: NSColor
    let tileShadow: NSColor

    init(mode: AppIcon.Mode) {
        switch mode {
        case .light:
            baseTop = NSColor(srgbRed: 0.99, green: 0.995, blue: 1.0, alpha: 1)
            baseBottom = NSColor(srgbRed: 0.91, green: 0.925, blue: 0.955, alpha: 1)
            baseStroke = NSColor(srgbRed: 0.80, green: 0.82, blue: 0.88, alpha: 0.58)
            micStroke = NSColor.black.withAlphaComponent(0.9)
            symbolShadow = NSColor.black.withAlphaComponent(0.14)
        case .dark:
            baseTop = NSColor(srgbRed: 0.135, green: 0.14, blue: 0.155, alpha: 1)
            baseBottom = NSColor(srgbRed: 0.045, green: 0.048, blue: 0.055, alpha: 1)
            baseStroke = NSColor.white.withAlphaComponent(0.10)
            micStroke = NSColor.white.withAlphaComponent(0.9)
            symbolShadow = NSColor.black.withAlphaComponent(0.38)
        }
        tileTop = NSColor(srgbRed: 0.67, green: 0.60, blue: 1.0, alpha: 1)
        tileBottom = NSColor(srgbRed: 0.30, green: 0.42, blue: 1.0, alpha: 1)
        tileStroke = NSColor.white.withAlphaComponent(0.24)
        tileShadow = NSColor.black.withAlphaComponent(mode == .dark ? 0.42 : 0.24)
    }
}
