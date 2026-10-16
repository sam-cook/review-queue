import AppKit
import ReviewQueueCore
import SwiftUI

struct TeamEditor: View {
    @ObservedObject var store: Store
    var snapshot = false  // ImageRenderer cannot draw AppKit-backed controls such as a text field
    @State private var draft = ""
    @State private var message: String?
    @State private var checking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.team.isEmpty ? "Add the GitHub usernames of the people whose PRs you review."
                                    : "Teammates whose PRs you review")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            VStack(spacing: 2) {
                ForEach(store.team, id: \.self) { user in
                    MemberRow(user: user, avatar: store.avatars[user]) { store.removeMember(user) }
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                if snapshot {
                    Text("GitHub username").font(.system(size: 13)).foregroundStyle(.tertiary)
                    Spacer()
                } else {
                    TextField("GitHub username", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focused)
                        .onSubmit(add)
                        .disabled(checking)
                }
                if checking { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(0.05)))
            if let message {
                Text(message).font(.system(size: 11)).foregroundStyle(.red).padding(.horizontal, 6)
            }
        }
        .onAppear { focused = store.team.isEmpty }
    }

    func add() {
        checking = true
        message = nil
        Task {
            let err = await store.addMember(draft)
            checking = false
            message = err
            if err == nil { draft = "" }
            focused = true
        }
    }
}

struct MemberRow: View {
    let user: String
    let avatar: NSImage?
    let remove: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Avatar(user: user, image: avatar)
            Text(user).font(.system(size: 13))
            Spacer()
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(.primary.opacity(hover ? 0.1 : 0)))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hover ? 1 : 0.4)
            .help("Remove \(user)")
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.primary.opacity(hover ? 0.05 : 0)))
        .onHover { hover = $0 }
    }
}

