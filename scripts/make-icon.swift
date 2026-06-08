// Renders the Drawer app icon master PNG (1024x1024).
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded square with Big Sur-style margins.
let margin: CGFloat = 100
let rect = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
let bg = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(
    starting: NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.28, alpha: 1),
    ending: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 1)
)!.draw(in: bg, angle: -90)

// Left drawer bar (the edge tab).
let bar = NSBezierPath(
    roundedRect: NSRect(x: margin + 88, y: size / 2 - 240, width: 64, height: 480),
    xRadius: 32, yRadius: 32
)
NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.16, alpha: 1).setFill()
bar.fill()

// Checkmark in a circle, drawn manually (no SF Symbol tint headaches).
let cx = margin + (rect.width * 0.60)
let cy = size / 2
let radius: CGFloat = 235
let stroke: CGFloat = 56

NSColor.white.setStroke()
let circle = NSBezierPath(ovalIn: NSRect(
    x: cx - radius, y: cy - radius, width: radius * 2, height: radius * 2
))
circle.lineWidth = stroke
circle.stroke()

let check = NSBezierPath()
check.lineWidth = stroke
check.lineCapStyle = .round
check.lineJoinStyle = .round
check.move(to: NSPoint(x: cx - 105, y: cy + 5))
check.line(to: NSPoint(x: cx - 30, y: cy - 80))
check.line(to: NSPoint(x: cx + 115, y: cy + 85))
check.stroke()

image.unlockFocus()

let tiff = image.tiffRepresentation!
let rep = NSBitmapImageRep(data: tiff)!
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
