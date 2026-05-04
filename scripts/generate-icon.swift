#!/usr/bin/env swift
//
// generate-icon.swift
// Builds the OpenType .icns file from Sources/Resources/AppIcon.png.
//
// Usage: swift generate-icon.swift <output-directory>
//   Produces <output-directory>/AppIcon.icns
//

import AppKit
import Foundation

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
    fputs("Usage: swift generate-icon.swift <output-directory> [source-png]\n", stderr)
    exit(1)
}

let outputDir = URL(fileURLWithPath: CommandLine.arguments[1])
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let projectDir = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let defaultSource = projectDir.appendingPathComponent("Sources/Resources/AppIcon.png").path
let sourcePath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : defaultSource

guard let icon = NSImage(contentsOfFile: sourcePath) else {
    fputs("Could not read icon source: \(sourcePath)\n", stderr)
    exit(1)
}

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
