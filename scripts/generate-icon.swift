#!/usr/bin/env swift

import AppKit

let canvasSize = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(canvasSize.width),
    pixelsHigh: Int(canvasSize.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create graphics context")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphicsContext
let context = graphicsContext.cgContext
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)

let outerRect = NSRect(x: 42, y: 42, width: 940, height: 940)
let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 220, yRadius: 220)
let backgroundGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.39, green: 0.16, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.00, green: 0.76, blue: 0.88, alpha: 1)
])!
backgroundGradient.draw(in: outerPath, angle: -48)

context.saveGState()
outerPath.addClip()
let glowPath = NSBezierPath(ovalIn: NSRect(x: 390, y: 430, width: 690, height: 690))
NSColor.white.withAlphaComponent(0.11).setFill()
glowPath.fill()
context.restoreGState()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -28), blur: 50, color: NSColor.black.withAlphaComponent(0.3).cgColor)

let rearCard = NSBezierPath(roundedRect: NSRect(x: 265, y: 205, width: 555, height: 600), xRadius: 76, yRadius: 76)
NSColor(calibratedWhite: 0.95, alpha: 0.58).setFill()
rearCard.fill()

let card = NSBezierPath(roundedRect: NSRect(x: 205, y: 160, width: 590, height: 650), xRadius: 82, yRadius: 82)
NSColor.white.setFill()
card.fill()
context.restoreGState()

let clipShadow = NSBezierPath(roundedRect: NSRect(x: 347, y: 715, width: 330, height: 145), xRadius: 68, yRadius: 68)
NSColor.black.withAlphaComponent(0.14).setFill()
clipShadow.fill()

let clip = NSBezierPath(roundedRect: NSRect(x: 337, y: 735, width: 330, height: 145), xRadius: 68, yRadius: 68)
let clipGradient = NSGradient(colors: [
    NSColor(calibratedRed: 1.00, green: 0.70, blue: 0.12, alpha: 1),
    NSColor(calibratedRed: 1.00, green: 0.33, blue: 0.28, alpha: 1)
])!
clipGradient.draw(in: clip, angle: -20)

let clipInner = NSBezierPath(roundedRect: NSRect(x: 427, y: 775, width: 150, height: 42), xRadius: 21, yRadius: 21)
NSColor.white.withAlphaComponent(0.9).setFill()
clipInner.fill()

let textColor = NSColor(calibratedRed: 0.18, green: 0.23, blue: 0.38, alpha: 1)
textColor.setFill()
for (index, width) in [390.0, 330.0, 370.0].enumerated() {
    let line = NSBezierPath(
        roundedRect: NSRect(x: 305, y: 580 - Double(index) * 92, width: width, height: 34),
        xRadius: 17,
        yRadius: 17
    )
    line.fill()
}

let historyCircle = NSBezierPath(ovalIn: NSRect(x: 490, y: 245, width: 205, height: 205))
let historyGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.39, green: 0.16, blue: 0.98, alpha: 1),
    NSColor(calibratedRed: 0.06, green: 0.55, blue: 0.95, alpha: 1)
])!
historyGradient.draw(in: historyCircle, angle: -45)

let arrow = NSBezierPath()
arrow.lineWidth = 24
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 642, y: 337))
arrow.curve(
    to: NSPoint(x: 548, y: 296),
    controlPoint1: NSPoint(x: 622, y: 292),
    controlPoint2: NSPoint(x: 575, y: 278)
)
NSColor.white.setStroke()
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.lineWidth = 24
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.move(to: NSPoint(x: 548, y: 296))
arrowHead.line(to: NSPoint(x: 557, y: 345))
arrowHead.move(to: NSPoint(x: 548, y: 296))
arrowHead.line(to: NSPoint(x: 596, y: 307))
arrowHead.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode icon")
}

let outputPath = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.png"
try pngData.write(to: URL(fileURLWithPath: outputPath))
