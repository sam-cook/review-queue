import AppKit

/// The menu bar icon: a pull-request symbol with a round count badge.
/// A template image (follows the menu bar's colour) unless something new needs you, then red.
enum StatusIcon {
    static let red = NSColor(srgbRed: 0.898, green: 0.325, blue: 0.294, alpha: 1)

    /// `count == nil` shows a warning symbol instead (no data, and an error).
    static func make(count: Int?, highlight: Bool) -> NSImage {
        let size = NSSize(width: count == nil ? 18 : 26, height: 18)
        let label = count.map { $0 > 99 ? "99+" : String($0) }
        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current else { return false }
            let fg: NSColor = highlight ? .labelColor : .black
            let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium).applying(.init(paletteColors: [fg]))
            let name = label == nil ? "exclamationmark.triangle" : "arrow.triangle.pull"
            if let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
                sym.draw(at: NSPoint(x: 1, y: (size.height - sym.size.height) / 2 - 1),
                         from: .zero, operation: .sourceOver, fraction: 1)
            }
            guard let label else { return true }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor.white]
            let ts = (label as NSString).size(withAttributes: attrs)
            let bh: CGFloat = 12, bw = max(bh, ts.width + 6)
            let r = NSRect(x: size.width - bw, y: size.height - bh, width: bw, height: bh)
            ctx.compositingOperation = .clear  // gap between icon and badge
            NSBezierPath(roundedRect: r.insetBy(dx: -1.5, dy: -1.5), xRadius: bh / 2 + 1.5, yRadius: bh / 2 + 1.5).fill()
            ctx.compositingOperation = .sourceOver
            (highlight ? red : .black).setFill()
            NSBezierPath(roundedRect: r, xRadius: bh / 2, yRadius: bh / 2).fill()
            if !highlight { ctx.compositingOperation = .destinationOut }  // knock digits out of the template pill
            (label as NSString).draw(at: NSPoint(x: r.midX - ts.width / 2, y: r.midY - ts.height / 2), withAttributes: attrs)
            return true
        }
        img.isTemplate = !highlight
        img.accessibilityDescription = count.map { "Review queue: \($0) pull requests need you" } ?? "Review queue: error"
        return img
    }
}
