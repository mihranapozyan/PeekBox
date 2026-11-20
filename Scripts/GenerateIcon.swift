//
//  GenerateIcon.swift
//  PeekBox
//
//  Created by Mihran on 20.11.26.
//

import AppKit

// App icon: dark rounded square with glowing lane-coloured shapes
// (here: three files rising out of an open box).
let destination = CommandLine.arguments[1]
let sizes = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var entries: [[String: Any]] = []

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
let blue = color(0.34, 0.64, 1.00), violet = color(0.74, 0.50, 1.00), mint = color(0.26, 0.82, 0.64), pink = color(1.00, 0.46, 0.66)

func glowing(_ tint: NSColor, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = tint.withAlphaComponent(0.55)
    glow.shadowBlurRadius = 30
    glow.set()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func draw() {
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
    NSGradient(starting: color(0.10, 0.11, 0.13), ending: color(0.17, 0.18, 0.21))!.draw(in: shape, angle: -90)
    color(1, 1, 1, 0.10).setStroke()
    shape.lineWidth = 4
    shape.stroke()

    // Three files fanned out above the box.
    let files: [(NSColor, CGFloat, CGFloat)] = [(blue, -150, 14), (mint, 150, -14), (violet, 0, 0)]
    for (tint, dx, angle) in files {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: 512 + dx, yBy: 470)
        transform.rotate(byDegrees: angle)
        transform.concat()
        let rect = NSRect(x: -88, y: 0, width: 176, height: 230)
        glowing(tint) {
            tint.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 30, yRadius: 30).fill()
        }
        // Text lines on the file.
        color(0.10, 0.11, 0.13, 0.55).setFill()
        for (i, width) in [110.0, 84.0, 110.0].enumerated() {
            NSBezierPath(roundedRect: NSRect(x: -55, y: 150 - CGFloat(i) * 40, width: width, height: 18), xRadius: 9, yRadius: 9).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // Open box in front.
    let box = NSBezierPath()
    box.move(to: NSPoint(x: 232, y: 520))
    box.line(to: NSPoint(x: 792, y: 520))
    box.line(to: NSPoint(x: 742, y: 250))
    box.curve(to: NSPoint(x: 692, y: 210), controlPoint1: NSPoint(x: 736, y: 222), controlPoint2: NSPoint(x: 720, y: 210))
    box.line(to: NSPoint(x: 332, y: 210))
    box.curve(to: NSPoint(x: 282, y: 250), controlPoint1: NSPoint(x: 304, y: 210), controlPoint2: NSPoint(x: 288, y: 222))
    box.close()
    NSGradient(starting: color(0.20, 0.21, 0.25), ending: color(0.26, 0.27, 0.31))!.draw(in: box, angle: 90)
    color(1, 1, 1, 0.14).setStroke()
    box.lineWidth = 5
    box.stroke()
    glowing(pink) {
        pink.setFill()
        NSBezierPath(roundedRect: NSRect(x: 437, y: 440, width: 150, height: 26), xRadius: 13, yRadius: 13).fill()
    }
}
for (base, scale) in sizes {
    let pixels = base * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    (AffineTransform(scale: CGFloat(pixels) / 1024) as NSAffineTransform).concat()
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let filename = "icon-\(base)@\(scale)x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
    entries.append(["idiom": "mac", "size": "\(base)x\(base)", "scale": "\(scale)x", "filename": filename])
}
let data = try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["author": "xcode", "version": 1]], options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: destination).appendingPathComponent("Contents.json"))
