#!/usr/bin/env swift
import AppKit
import Foundation

enum IconMode { case light, dark }

func run(_ executable: String, _ arguments: [String], quiet: Bool = false) throws {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments
    if quiet {
        task.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
    }
    try task.run()
    task.waitUntilExit()
    guard task.terminationStatus == 0 else {
        let message = "\(executable) failed with status \(task.terminationStatus)"
        throw NSError(domain: "OpenTypeIconGeneration", code: Int(task.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: message
        ])
    }
}

func renderForeground(size: CGFloat, mode: IconMode) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        guard let context = NSGraphicsContext.current?.cgContext else { return false }
        let palette = Palette(mode: mode)
        context.clear(rect)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        drawForeground(in: foregroundRect(in: rect), context: context, palette: palette)
        return true
    }
}

func foregroundRect(in rect: CGRect) -> CGRect {
    let side = min(rect.width, rect.height)
    let baseRect = rect.insetBy(dx: side * 0.015, dy: side * 0.015)
    return baseRect.insetBy(dx: baseRect.width * 0.09, dy: baseRect.height * 0.09)
}

func drawForeground(in rect: CGRect, context: CGContext, palette: Palette) {
    drawMicrophone(in: rect, context: context, palette: palette)
    drawWaveTile(in: rect, context: context, palette: palette)
}

func drawMicrophone(in rect: CGRect, context: CGContext, palette: Palette) {
    let width = rect.width
    let centerX = rect.midX
    let topY = rect.minY + width * 0.49
    let bottomY = rect.minY + width * 0.255
    let leftX = centerX - width * 0.31
    let rightX = centerX + width * 0.31

    let cup = CGMutablePath()
    cup.move(to: CGPoint(x: leftX, y: topY))
    cup.addCurve(to: CGPoint(x: centerX, y: bottomY), control1: CGPoint(x: leftX, y: rect.minY + width * 0.34), control2: CGPoint(x: centerX - width * 0.2, y: bottomY))
    cup.addCurve(to: CGPoint(x: rightX, y: topY), control1: CGPoint(x: centerX + width * 0.2, y: bottomY), control2: CGPoint(x: rightX, y: rect.minY + width * 0.34))

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -width * 0.012), blur: width * 0.028, color: palette.symbolShadow.cgColor)
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

    let base = CGRect(x: centerX - width * 0.105, y: rect.minY + width * 0.115, width: width * 0.21, height: width * 0.06)
    context.setFillColor(palette.micStroke.cgColor)
    context.addPath(CGPath(roundedRect: base, cornerWidth: base.height / 2, cornerHeight: base.height / 2, transform: nil))
    context.fillPath()
}

func drawWaveTile(in rect: CGRect, context: CGContext, palette: Palette) {
    let width = rect.width
    let tileSide = width * 0.43
    let tile = CGRect(x: rect.midX - tileSide / 2, y: rect.minY + width * 0.365, width: tileSide, height: tileSide)
    let tileRadius = tileSide * 0.22
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -width * 0.025), blur: width * 0.05, color: palette.tileShadow.cgColor)
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
    context.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
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
        let bar = CGRect(x: startX + CGFloat(index) * (barWidth + gap), y: tile.midY - height / 2, width: barWidth, height: height)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil))
        context.fillPath()
    }
}

func savePNG(_ image: NSImage, to url: URL, pixels: Int) throws {
    try saveCenteredPNG(image, to: url, pixels: pixels, scale: 1)
}

func saveCenteredPNG(_ image: NSImage, to url: URL, pixels: Int, scale: CGFloat) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: pixels, height: pixels)

    let side = CGFloat(pixels) * scale
    let imageRect = NSRect(x: (CGFloat(pixels) - side) / 2, y: (CGFloat(pixels) - side) / 2, width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
    image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "OpenTypeIconGeneration", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Failed to encode PNG"
        ])
    }
    try data.write(to: url, options: .atomic)
}

func writeIconComposerSource(at url: URL, foreground: NSImage, mode: IconMode) throws {
    let assetsURL = url.appendingPathComponent("Assets")
    try FileManager.default.createDirectory(at: assetsURL, withIntermediateDirectories: true)
    try savePNG(foreground, to: assetsURL.appendingPathComponent("artwork.png"), pixels: 1024)

    let fill = mode == .dark
        ? "extended-srgb:0.07000,0.07400,0.08300,1.00000"
        : "extended-srgb:0.95500,0.97000,0.99500,1.00000"
    let json = """
    {"fill":{"automatic-gradient":"\(fill)"},"groups":[{"layers":[{"image-name":"artwork.png","name":"OpenType Foreground"}],"shadow":{"kind":"neutral","opacity":0},"translucency":{"enabled":false,"value":0}}],"supported-platforms":{"circles":["watchOS"],"squares":"shared"}}
    """
    try json.data(using: .utf8)!.write(to: url.appendingPathComponent("icon.json"), options: .atomic)
}

struct Palette {
    let micStroke: NSColor
    let symbolShadow: NSColor
    let tileTop: NSColor
    let tileBottom: NSColor
    let tileStroke: NSColor
    let tileShadow: NSColor

    init(mode: IconMode) {
        switch mode {
        case .light:
            micStroke = NSColor.black.withAlphaComponent(0.9)
            symbolShadow = NSColor.black.withAlphaComponent(0.14)
        case .dark:
            micStroke = NSColor.white.withAlphaComponent(0.9)
            symbolShadow = NSColor.black.withAlphaComponent(0.38)
        }
        tileTop = NSColor(srgbRed: 0.67, green: 0.60, blue: 1.0, alpha: 1)
        tileBottom = NSColor(srgbRed: 0.30, green: 0.42, blue: 1.0, alpha: 1)
        tileStroke = NSColor.white.withAlphaComponent(0.24)
        tileShadow = NSColor.black.withAlphaComponent(mode == .dark ? 0.42 : 0.24)
    }
}

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift generate-icon.swift <output-directory>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let rendition = ProcessInfo.processInfo.environment["OPENTYPE_ICON_RENDITION"] ?? "Light"
let outputName = ProcessInfo.processInfo.environment["OPENTYPE_ICON_OUTPUT_NAME"] ?? "AppIcon.icns"
let canvasScale = CGFloat(Double(ProcessInfo.processInfo.environment["OPENTYPE_ICON_CANVAS_SCALE"] ?? "") ?? 0.84)
let mode: IconMode = rendition.caseInsensitiveCompare("Dark") == .orderedSame ? .dark : .light
let ictoolPath = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256),
    ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

do {
    guard FileManager.default.fileExists(atPath: ictoolPath) else {
        throw NSError(domain: "OpenTypeIconGeneration", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Missing Icon Composer tool: \(ictoolPath)"
        ])
    }

    let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("OpenTypeAppIcon-\(UUID().uuidString).icon")
    try writeIconComposerSource(at: sourceURL, foreground: renderForeground(size: 1024, mode: mode), mode: mode)
    if let keepPath = ProcessInfo.processInfo.environment["OPENTYPE_ICON_SOURCE_DIR"], !keepPath.isEmpty {
        let keepURL = URL(fileURLWithPath: keepPath)
        try FileManager.default.createDirectory(at: keepURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: keepURL)
        try FileManager.default.copyItem(at: sourceURL, to: keepURL)
    }
    defer { try? FileManager.default.removeItem(at: sourceURL) }

    for entry in sizes {
        let url = iconsetDir.appendingPathComponent("\(entry.name).png")
        let composerURL = iconsetDir.appendingPathComponent("composer-\(entry.name).png")
        try run(ictoolPath, [
            sourceURL.path,
            "--export-image",
            "--output-file", composerURL.path,
            "--platform", "macOS",
            "--rendition", "Default",
            "--width", "\(entry.pixels)",
            "--height", "\(entry.pixels)",
            "--scale", "1",
        ], quiet: true)
        try? FileManager.default.removeItem(at: url)
        guard let image = NSImage(contentsOf: composerURL) else {
            throw NSError(domain: "OpenTypeIconGeneration", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Failed to read Icon Composer output"
            ])
        }
        try saveCenteredPNG(image, to: url, pixels: entry.pixels, scale: canvasScale)
        try? FileManager.default.removeItem(at: composerURL)
    }

    let icnsPath = outputDir.appendingPathComponent(outputName).path
    try run("/usr/bin/iconutil", ["-c", "icns", iconsetDir.path, "-o", icnsPath])
    try? FileManager.default.removeItem(at: iconsetDir)
    print("\(outputName) (\(rendition)) -> \(icnsPath)")
} catch {
    fputs("\(error.localizedDescription)\n", stderr)
    exit(1)
}
