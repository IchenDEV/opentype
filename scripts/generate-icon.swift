#!/usr/bin/env swift
//
// generate-icon.swift
// Renders the OpenType app icon into an .icns file.
//
// Usage: swift generate-icon.swift <output-directory>
//   Produces <output-directory>/AppIcon.icns
//

import AppKit
import Foundation

// MARK: - Icon rendering (mirrors Sources/App/AppIcon.swift)

func renderIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let ctx = NSGraphicsContext.current!.cgContext

        let inset = size * 0.1
        let iconRect = rect.insetBy(dx: inset, dy: inset)
        let cornerRadius = iconRect.width * 0.22

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

        let cx = iconRect.midX
        let cy = iconRect.midY
        let glyphR = iconRect.width * 0.30

        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(iconRect.width * 0.025)
        ctx.addArc(center: CGPoint(x: cx, y: cy), radius: glyphR,
                   startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

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

func savePNG(_ image: NSImage, to url: URL, pixelSize: Int) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    NSGraphicsContext.restoreGraphicsState()

    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: url)
}

// MARK: - Main

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift generate-icon.swift <output-directory>\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
let iconsetDir = outputDir.appendingPathComponent("AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16",      16),
    ("icon_16x16@2x",   32),
    ("icon_32x32",      32),
    ("icon_32x32@2x",   64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x", 1024),
]

let icon = renderIcon(size: 1024)

for entry in sizes {
    let url = iconsetDir.appendingPathComponent("\(entry.name).png")
    savePNG(icon, to: url, pixelSize: entry.pixels)
}

let icnsPath = outputDir.appendingPathComponent("AppIcon.icns").path
let iconsetPath = iconsetDir.path

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try! task.run()
task.waitUntilExit()

try? FileManager.default.removeItem(at: iconsetDir)

if task.terminationStatus == 0 {
    print("AppIcon.icns -> \(icnsPath)")
} else {
    fputs("iconutil failed with status \(task.terminationStatus)\n", stderr)
    exit(1)
}
