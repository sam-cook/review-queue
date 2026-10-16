import SwiftUI

/// Snapshots only: the menu bar icon in its states, on a menu-bar-like strip.
struct IconStrip: View {
    let dark: Bool

    var body: some View {
        HStack(spacing: 28) {
            item(StatusIcon.make(count: 3, highlight: false), "3 need you")
            item(StatusIcon.make(count: 4, highlight: true, foreground: dark ? .white : .black), "Something new")
            item(StatusIcon.make(count: 0, highlight: false), "All caught up")
            item(StatusIcon.make(count: nil, highlight: false), "Can't reach GitHub")
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(dark ? Color(white: 0.13) : Color(white: 0.93))
    }

    func item(_ img: NSImage, _ caption: String) -> some View {
        VStack(spacing: 8) {
            // Template images take the menu bar's colour; draw them as the menu bar would.
            Image(nsImage: img).renderingMode(img.isTemplate ? .template : .original)
                .foregroundStyle(dark ? .white : .black)
                .scaleEffect(1.6).frame(height: 30)
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}
