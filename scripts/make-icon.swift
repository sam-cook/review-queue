// Draws the app icon (a pull-request symbol on a rounded square) into an .iconset folder.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px), inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(starting: NSColor(srgbRed: 0.33, green: 0.38, blue: 0.95, alpha: 1),
               ending: NSColor(srgbRed: 0.55, green: 0.30, blue: 0.90, alpha: 1))!.draw(in: bg, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold).applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "arrow.triangle.pull", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        sym.draw(in: NSRect(x: (s - sym.size.width) / 2, y: (s - sym.size.height) / 2, width: sym.size.width, height: sym.size.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try draw(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
