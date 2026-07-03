#!/usr/bin/env swift

import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first ?? ""
guard !outputPath.isEmpty else {
    fputs("Usage: generate_icon.swift <output-iconset-path>\n", stderr)
    exit(1)
}

let fileManager = FileManager.default
let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)

try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(filename: String, points: CGFloat, pixels: CGFloat)] = [
    ("icon_16x16.png", 16, 16),
    ("icon_16x16@2x.png", 16, 32),
    ("icon_32x32.png", 32, 32),
    ("icon_32x32@2x.png", 32, 64),
    ("icon_128x128.png", 128, 128),
    ("icon_128x128@2x.png", 128, 256),
    ("icon_256x256.png", 256, 256),
    ("icon_256x256@2x.png", 256, 512),
    ("icon_512x512.png", 512, 512),
    ("icon_512x512@2x.png", 512, 1024),
]

func drawIcon(size: CGFloat, pixels: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let background = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.035, dy: size * 0.035), xRadius: size * 0.22, yRadius: size * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.08, green: 0.42, blue: 0.85, alpha: 1.0),
        NSColor(calibratedRed: 0.04, green: 0.11, blue: 0.24, alpha: 1.0),
    ])!
    gradient.draw(in: background, angle: -90)

    let haloRect = NSRect(x: size * 0.18, y: size * 0.57, width: size * 0.54, height: size * 0.19)
    let haloPath = NSBezierPath(ovalIn: haloRect)
    NSColor(calibratedRed: 0.68, green: 0.90, blue: 1.0, alpha: 0.18).setFill()
    haloPath.fill()

    let externalBody = NSBezierPath(roundedRect: NSRect(x: size * 0.45, y: size * 0.43, width: size * 0.34, height: size * 0.23), xRadius: size * 0.04, yRadius: size * 0.04)
    NSColor(calibratedWhite: 1.0, alpha: 0.98).setFill()
    externalBody.fill()

    let externalInner = NSBezierPath(roundedRect: NSRect(x: size * 0.475, y: size * 0.455, width: size * 0.29, height: size * 0.18), xRadius: size * 0.025, yRadius: size * 0.025)
    let externalGradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.78, green: 0.95, blue: 1.0, alpha: 1.0),
        NSColor(calibratedRed: 0.26, green: 0.67, blue: 0.98, alpha: 1.0),
    ])!
    externalGradient.draw(in: externalInner, angle: -90)

    let stand = NSBezierPath()
    stand.move(to: NSPoint(x: size * 0.62, y: size * 0.43))
    stand.line(to: NSPoint(x: size * 0.60, y: size * 0.33))
    stand.line(to: NSPoint(x: size * 0.64, y: size * 0.33))
    stand.close()
    NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
    stand.fill()

    let standBase = NSBezierPath(roundedRect: NSRect(x: size * 0.54, y: size * 0.28, width: size * 0.16, height: size * 0.028), xRadius: size * 0.014, yRadius: size * 0.014)
    NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
    standBase.fill()

    let lidStroke = NSBezierPath()
    lidStroke.move(to: NSPoint(x: size * 0.24, y: size * 0.33))
    lidStroke.line(to: NSPoint(x: size * 0.44, y: size * 0.57))
    lidStroke.lineWidth = max(4, size * 0.03)
    lidStroke.lineCapStyle = .round
    NSColor(calibratedWhite: 1.0, alpha: 0.97).setStroke()
    lidStroke.stroke()

    let lidGlow = NSBezierPath()
    lidGlow.move(to: NSPoint(x: size * 0.27, y: size * 0.35))
    lidGlow.line(to: NSPoint(x: size * 0.43, y: size * 0.54))
    lidGlow.lineWidth = max(2, size * 0.012)
    lidGlow.lineCapStyle = .round
    NSColor(calibratedRed: 0.67, green: 0.93, blue: 1.0, alpha: 0.8).setStroke()
    lidGlow.stroke()

    let baseFill = NSBezierPath()
    baseFill.move(to: NSPoint(x: size * 0.16, y: size * 0.27))
    baseFill.line(to: NSPoint(x: size * 0.43, y: size * 0.27))
    baseFill.line(to: NSPoint(x: size * 0.39, y: size * 0.21))
    baseFill.line(to: NSPoint(x: size * 0.19, y: size * 0.21))
    baseFill.close()
    NSColor(calibratedWhite: 1.0, alpha: 0.96).setFill()
    baseFill.fill()

    let baseShadow = NSBezierPath(roundedRect: NSRect(x: size * 0.18, y: size * 0.195, width: size * 0.22, height: size * 0.018), xRadius: size * 0.009, yRadius: size * 0.009)
    NSColor(calibratedWhite: 0.8, alpha: 0.65).setFill()
    baseShadow.fill()

    let connector = NSBezierPath()
    connector.move(to: NSPoint(x: size * 0.45, y: size * 0.43))
    connector.curve(
        to: NSPoint(x: size * 0.39, y: size * 0.35),
        controlPoint1: NSPoint(x: size * 0.43, y: size * 0.37),
        controlPoint2: NSPoint(x: size * 0.40, y: size * 0.36)
    )
    connector.lineWidth = max(3, size * 0.02)
    connector.lineCapStyle = .round
    NSColor(calibratedWhite: 1.0, alpha: 0.84).setStroke()
    connector.stroke()

    image.unlockFocus()
    image.size = NSSize(width: pixels, height: pixels)
    return image
}

for item in sizes {
    autoreleasepool {
        let image = drawIcon(size: item.points, pixels: item.pixels)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            fputs("Failed to generate \(item.filename)\n", stderr)
            exit(1)
        }
        let fileURL = outputURL.appendingPathComponent(item.filename)
        try? png.write(to: fileURL)
    }
}
