import AppKit
import ReviewQueueCore
import SwiftUI

/// A titled group of PR rows; optionally collapsible.
struct QueueSection: View {
    let title: String
    let prs: [PR]
    @ObservedObject var store: Store
    var empty: String? = nil
    var collapsible = false
    @State private var open = false

    var body: some View {
        if prs.isEmpty && empty == nil { EmptyView() } else {
            VStack(alignment: .leading, spacing: 2) {
                Button { if collapsible { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } } label: {
                    HStack(spacing: 6) {
                        Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).kerning(0.4)
                        if !prs.isEmpty { Text("\(prs.count)").font(.system(size: 10.5).monospacedDigit()) }
                        if collapsible {
                            Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
                                .rotationEffect(.degrees(open ? 90 : 0))
                        }
                        Spacer()
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8).padding(.bottom, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if prs.isEmpty, let empty {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text(empty).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12.5))
                    .padding(.horizontal, 8).padding(.vertical, 8)
                }
                if !collapsible || open {
                    ForEach(prs, id: \.url) { pr in
                        PRRow(pr: pr, avatar: store.avatars[pr.author], isNew: store.newKeys.contains(pr.key),
                              hidden: store.isHidden(pr), store: store)
                            .opacity(pr.reason.needsMe && !store.isHidden(pr) ? 1 : 0.6)
                    }
                }
            }
        }
    }
}

struct PRRow: View {
    let pr: PR
    let avatar: NSImage?
    let isNew: Bool
    let hidden: Bool
    @ObservedObject var store: Store
    @State private var hover = false

    var ci: CIStatus.Summary { CIStatus.summary(pr.ci) }

    var body: some View {
        Button {
            NSWorkspace.shared.open(pr.url)
            NSApp.keyWindow?.close()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Avatar(user: pr.author, image: avatar, size: 22)
                    .overlay(alignment: .topTrailing) {
                        if isNew {
                            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                                .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                                .offset(x: 2, y: -2)
                        }
                    }
                    .help(pr.author)
                VStack(alignment: .leading, spacing: 4) {
                    Text(pr.title)
                        .font(.system(size: 13, weight: isNew ? .semibold : .regular))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Pill(text: pr.label, color: pr.reason.tone.color)
                        if pr.othersApproved { Pill(text: "Approved", color: .green).help("Approved by someone else; it may merge soon") }
                        if pr.myOpenThreads > 0 {
                            Pill(text: "\(pr.myOpenThreads) open", color: .secondary).help("Your unresolved review threads")
                        }
                        Circle().fill(ci.color).frame(width: 6, height: 6).help(ci.help).accessibilityLabel(ci.help)
                        Text(verbatim: "\(pr.repo.split(separator: "/").last ?? "")#\(pr.number)")
                            .lineLimit(1).truncationMode(.middle)
                        Text("·").foregroundStyle(.quaternary)
                        Text(rowDateFormat.string(from: pr.created)).fixedSize()
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hover ? Color.primary.opacity(0.07) : .clear))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hover {
                RowAction(systemName: hidden ? "arrow.uturn.backward" : "xmark",
                          help: hidden ? "Restore" : "Dismiss until something changes") {
                    withAnimation(.easeOut(duration: 0.15)) { hidden ? store.restore(pr) : store.dismiss(pr) }
                }
                .padding(6)
            }
        }
        .onHover { hover = $0 }
        .help("\(pr.author) · \(pr.repo)#\(pr.number)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pr.label): \(pr.title), by \(pr.author), \(pr.repo) number \(pr.number)")
        .contextMenu {
            Button("Open in Browser") { NSWorkspace.shared.open(pr.url) }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
            }
            Divider()
            if hidden {
                Button("Restore") { store.restore(pr) }
            } else {
                Button("Dismiss Until Something Changes") { store.dismiss(pr) }
                Button("Always Hide This PR") { store.mute(pr) }
            }
        }
    }
}

