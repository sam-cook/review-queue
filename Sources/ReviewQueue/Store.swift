import AppKit
import ReviewQueueCore
import ServiceManagement
import UserNotifications

/// The app's single source of truth: the PR list, the team, and refresh scheduling.
@MainActor
final class Store: ObservableObject {
    @Published var prs: [PR] = []
    @Published var error: String?
    @Published var updated: Date?
    @Published var loading = false
    @Published var newKeys: Set<String> = []  // needed you since last open; highlighted while the panel is open
    @Published var avatars: [String: NSImage] = [:]
    @Published var icon = StatusIcon.make(count: 0, highlight: false)
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var state: QueueState

    @Published var team: [String] {
        didSet { persistence.saveTeam(team); if live { refresh() } }
    }

    let settings: Settings
    let client: GitHubClient
    private let persistence: Persistence
    private let notifier: Notifier?
    private var timer: Timer?
    private var refreshAgain = false
    private var pausedUntil: Date?  // set after hitting the GitHub rate limit
    private var avatarRequests: Set<String> = []
    /// False for demo and snapshot stores: they never contact GitHub.
    private let live: Bool

    init(settings: Settings, client: GitHubClient, persistence: Persistence = Persistence(), notifier: Notifier? = Notifier(),
         autoRefresh: Bool = true) {
        self.settings = settings
        self.client = client
        self.persistence = persistence
        self.notifier = notifier
        self.live = autoRefresh
        self.state = persistence.loadState()
        self.team = persistence.loadTeam()
        guard autoRefresh else { return }
        notifier?.requestPermission()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: Derived lists

    var visible: [PR] { state.visible(prs) }
    var hidden: [PR] { state.hidden(prs) }
    var needsMe: [PR] { state.needsMe(prs) }
    func isHidden(_ pr: PR) -> Bool { state.isHidden(pr) }

    // MARK: Actions

    func dismiss(_ pr: PR) { update { $0.dismiss(pr) } }
    func mute(_ pr: PR) { update { $0.mute(pr) } }
    func restore(_ pr: PR) { update { $0.restore(pr) } }

    func refresh(manual: Bool = false) {
        guard live else { return }
        guard !loading else { refreshAgain = true; return }  // e.g. team changed mid-fetch
        if !manual, let p = pausedUntil, p > Date() { return }
        loading = true
        Task {
            do {
                let (_, prs, warning) = try await client.fetchQueue(team: team)
                self.prs = prs
                self.error = warning
                self.updated = Date()
                self.pausedUntil = nil
                var s = state
                let fresh = s.applyRefresh(prs)
                setState(s)
                notifier?.announce(fresh)
            } catch GitHubError.rateLimited {
                let until = Date().addingTimeInterval(10 * 60)
                pausedUntil = until
                error = "GitHub rate limit reached. Retrying at \(until.formatted(date: .omitted, time: .shortened))."
            } catch {
                self.error = error.localizedDescription
            }
            loading = false
            updateIcon()
            loadAvatars()
            if refreshAgain { refreshAgain = false; refresh() }
        }
    }

    func didOpen() {
        // Catch PRs that closed or changed since the last timed refresh.
        if Date().timeIntervalSince(updated ?? .distantPast) > 60 { refresh() }
        newKeys = state.unseen(prs)
        update { [prs] in $0.markSeen(prs) }
    }

    func didClose() { newKeys = [] }

    /// Adds a teammate after checking the username exists. Returns an error message, or nil.
    func addMember(_ raw: String) async -> String? {
        let name = cleanLogin(raw)
        guard !name.isEmpty else { return nil }
        if team.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return "Already in the team" }
        do {
            guard let login = try await client.lookupUser(name) else { return "No user “\(name)” on \(settings.host)" }
            team.append(login)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func removeMember(_ name: String) { team.removeAll { $0 == name } }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Internals

    /// Replaces the list without fetching (demo and snapshot modes).
    func show(_ prs: [PR]) {
        self.prs = prs.sorted(by: PR.queueOrder)
        updated = Date()
        updateIcon()
    }

    private func update(_ change: (inout QueueState) -> Void) {
        var s = state
        change(&s)
        setState(s)
    }

    private func setState(_ s: QueueState) {
        state = s
        persistence.save(s)
        updateIcon()
    }

    func updateIcon() {
        icon = error != nil && prs.isEmpty
            ? StatusIcon.make(count: nil, highlight: false)
            : StatusIcon.make(count: needsMe.count, highlight: !state.unseen(prs).isEmpty)
    }

    /// Avatars load once per person and stay in memory.
    private func loadAvatars() {
        guard live else { return }
        var wanted: [String: URL] = [:]
        for u in team { if let url = settings.avatarURL(for: u) { wanted[u] = url } }
        for pr in prs { if let a = pr.avatar { wanted[pr.author] = a } }
        for (user, url) in wanted where avatars[user] == nil && !avatarRequests.contains(user) {
            avatarRequests.insert(user)
            Task {
                if let data = await client.avatar(url), let img = NSImage(data: data) { avatars[user] = img }
                else { avatarRequests.remove(user) }  // try again on the next refresh
            }
        }
    }
}
