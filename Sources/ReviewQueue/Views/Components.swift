import AppKit
import ReviewQueueCore
import SwiftUI

struct Avatar: View {
    let user: String
    let image: NSImage?
    var size: CGFloat = 18
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable() }
            else { Circle().fill(.primary.opacity(0.1)).overlay(
                Text(user.prefix(1).uppercased()).font(.system(size: size / 2, weight: .semibold)).foregroundStyle(.secondary)) }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct RowAction: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.regularMaterial))
                .overlay(Circle().stroke(Color.primary.opacity(hover ? 0.2 : 0.08)))
                .foregroundStyle(hover ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .fixedSize()
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}

struct IconButton: View {
    let systemName: String
    var spinning = false
    var help = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hover ? Color.primary.opacity(0.08) : .clear))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
    }
}
