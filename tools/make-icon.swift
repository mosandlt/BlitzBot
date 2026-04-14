import AppKit
import Foundation

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath)
    .appendingPathComponent("blitzbot.iconset")

try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(size: Int) -> Data? {
    let dim = CGFloat(size)
    let img = NSImage(size: NSSize(width: dim, height: dim))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus(); return nil
    }

    // rounded yellow-orange background
    let radius = dim * 0.22
    let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: dim, height: dim),
                              xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.86, blue: 0.20, alpha: 1.0),
        NSColor(srgbRed: 0.99, green: 0.66, blue: 0.08, alpha: 1.0)
    ])!
    gradient.draw(in: bgPath, angle: -90)

    // hand-drawn lightning bolt (classic zig-zag shape)
    let bolt = NSBezierPath()
    let w = dim, h = dim
    // coordinates roughly centered, points go counterclockwise
    let points: [(CGFloat, CGFloat)] = [
        (0.56, 0.94), // top right
        (0.26, 0.50), // middle-left indent
        (0.44, 0.50),
        (0.34, 0.06), // bottom tip
        (0.72, 0.58),
        (0.52, 0.58),
        (0.66, 0.94)
    ]
    bolt.move(to: NSPoint(x: points[0].0 * w, y: points[0].1 * h))
    for p in points.dropFirst() {
        bolt.line(to: NSPoint(x: p.0 * w, y: p.1 * h))
    }
    bolt.close()

    // subtle shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -dim * 0.01),
                  blur: dim * 0.03,
                  color: NSColor.black.withAlphaComponent(0.35).cgColor)
    NSColor(srgbRed: 0.10, green: 0.08, blue: 0.04, alpha: 1.0).setFill()
    bolt.fill()
    ctx.restoreGState()

    // bright highlight stroke
    NSColor.white.withAlphaComponent(0.18).setStroke()
    bolt.lineWidth = dim * 0.012
    bolt.stroke()

    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return nil }
    return png
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (size, name) in sizes {
    guard let data = render(size: size) else { continue }
    let url = outDir.appendingPathComponent(name)
    try data.write(to: url)
    print("wrote \(name) (\(size)px)")
}
print("iconset: \(outDir.path)")
