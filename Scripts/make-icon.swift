// Draws the app icon: a rounded note card with a folded corner and a few text lines.
// Used by Scripts/build.sh; writes a 1024x1024 PNG to the path given as argv[1].
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let bounds = NSRect(x: 0, y: 0, width: size, height: size)
// Background: rounded square with a soft vertical gradient.
let card = NSBezierPath(roundedRect: bounds.insetBy(dx: size * 0.07, dy: size * 0.07),
                        xRadius: size * 0.22, yRadius: size * 0.22)
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0.29, green: 0.35, blue: 0.98, alpha: 1),
    NSColor(srgbRed: 0.52, green: 0.30, blue: 0.92, alpha: 1),
])!
gradient.draw(in: card, angle: -90)

// The note sheet.
let sheet = NSRect(x: size * 0.245, y: size * 0.205, width: size * 0.51, height: size * 0.59)
let paper = NSBezierPath(roundedRect: sheet, xRadius: size * 0.055, yRadius: size * 0.055)
NSColor(white: 1, alpha: 0.96).setFill()
paper.fill()

// Text lines: a title bar plus three body lines, the last one short.
NSColor(srgbRed: 0.29, green: 0.35, blue: 0.98, alpha: 0.85).setFill()
NSBezierPath(roundedRect: NSRect(x: sheet.minX + size * 0.06, y: sheet.maxY - size * 0.14,
                                 width: size * 0.28, height: size * 0.045),
             xRadius: size * 0.022, yRadius: size * 0.022).fill()

NSColor(white: 0.62, alpha: 1).setFill()
let lineWidths: [CGFloat] = [0.39, 0.33, 0.2]
for (index, factor) in lineWidths.enumerated() {
    let y = sheet.maxY - size * 0.28 - CGFloat(index) * size * 0.105
    NSBezierPath(roundedRect: NSRect(x: sheet.minX + size * 0.06, y: y,
                                     width: size * factor, height: size * 0.032),
                 xRadius: size * 0.016, yRadius: size * 0.016).fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("icon: failed to render\n".utf8))
    exit(1)
}
try png.write(to: URL(fileURLWithPath: out))
print(out)
