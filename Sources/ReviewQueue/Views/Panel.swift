import AppKit
import ReviewQueueCore
import SwiftUI

struct Panel: View {
    @ObservedObject var store: Store
    var snapshot = false  // ImageRenderer cannot draw a ScrollView

    /// The menu bar panel: sections for PRs that need you, your PRs, waiting, and dismissed.
    @State var editing = false
    /// Snapshots only: start with the collapsible sections open.
    var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            scrolling {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = store.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.red)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.red.opacity(0.08)))
                    }
                    if editing || store.team.isEmpty {
                        TeamEditor(store: store, snapshot: snapshot)
                    } else {
                        QueueSection(title: "Needs your review", prs: store.needsMe.filter { !$0.isMine }, store: store,
                                empty: "You are all caught up")
                        QueueSection(title: "Your PRs", prs: store.needsMe.filter(\.isMine), store: store)
                        QueueSection(title: "Waiting", prs: store.visible.filter { !$0.reason.needsMe }, store: store,
                                collapsible: true, open: expanded)
                        QueueSection(title: "Dismissed", prs: store.hidden, store: store, collapsible: true, open: expanded)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 410)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in store.didOpen() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in store.didClose() }
    }

    @ViewBuilder func scrolling<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        if snapshot { content() }
        else { ScrollView { content() }.frame(maxHeight: 520).fixedSize(horizontal: false, vertical: true) }
    }

    var header: some View {
        HStack(spacing: 8) {
            Text(editing || store.team.isEmpty ? "Team" : "Review queue").font(.system(size: 13, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text("\(store.needsMe.count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(Capsule().fill(.primary.opacity(0.08)))
                .foregroundStyle(.secondary)
            Spacer()
            if let updated = store.updated {
                Text(updated, style: .time).font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            IconButton(systemName: editing ? "checkmark" : "person.2", help: editing ? "Done" : "Edit team") {
                editing.toggle()
            }
            IconButton(systemName: "arrow.clockwise", spinning: store.loading, help: "Refresh") { store.refresh(manual: true) }
                .keyboardShortcut("r")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    var footer: some View {
        HStack {
            if snapshot {
                // ImageRenderer cannot draw AppKit-backed controls such as a switch.
                Text("Launch at login").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.settings.isGitHubDotCom {
                Text(store.settings.host).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

