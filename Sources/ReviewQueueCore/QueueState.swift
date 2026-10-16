import Foundation

/// The viewer's choices and history that outlive a refresh: what they dismissed, muted, saw and
/// were notified about. Pure value type; `Persistence` saves it.
public struct QueueState: Equatable, Sendable {
    /// PR keys dismissed "until something changes". A key changes when the PR needs the viewer again.
    public var dismissed: Set<String> = []
    /// PR URLs hidden for good.
    public var muted: Set<String> = []
    /// PR keys the viewer has seen in the open panel; nil before the first refresh ever.
    public var seen: Set<String>?
    /// PR keys already announced with a notification.
    public var notified: [String] = []

    public static let notifiedLimit = 500

    public init() {}

    public func isHidden(_ pr: PR) -> Bool { dismissed.contains(pr.key) || muted.contains(pr.url.absoluteString) }
    public func visible(_ prs: [PR]) -> [PR] { prs.filter { !isHidden($0) } }
    public func hidden(_ prs: [PR]) -> [PR] { prs.filter(isHidden) }
    public func needsMe(_ prs: [PR]) -> [PR] { visible(prs).filter { $0.reason.needsMe } }

    /// Keys that need the viewer and have not been seen yet: these make the badge red.
    public func unseen(_ prs: [PR]) -> Set<String> {
        let s = seen ?? []
        return Set(needsMe(prs).map(\.key).filter { !s.contains($0) })
    }

    public mutating func dismiss(_ pr: PR) { dismissed.insert(pr.key) }
    public mutating func mute(_ pr: PR) { muted.insert(pr.url.absoluteString) }
    public mutating func restore(_ pr: PR) {
        dismissed.remove(pr.key)
        muted.remove(pr.url.absoluteString)
    }

    /// The panel opened: everything currently needing the viewer counts as seen.
    public mutating func markSeen(_ prs: [PR]) { seen = Set(needsMe(prs).map(\.key)) }

    /// After a refresh: returns the PRs to notify about, and updates history.
    /// - The very first refresh announces nothing (everything is old news).
    /// - Each key is announced once.
    /// - Dismissals for PRs that changed or left the list are dropped.
    public mutating func applyRefresh(_ prs: [PR]) -> [PR] {
        if seen == nil {
            let keys = needsMe(prs).map(\.key)
            seen = Set(keys)
            notified = Array(keys.suffix(Self.notifiedLimit))
        }
        let announced = Set(notified)
        let fresh = needsMe(prs).filter { !announced.contains($0.key) && !(seen ?? []).contains($0.key) }
        notified = Array((notified + fresh.map(\.key)).suffix(Self.notifiedLimit))
        dismissed.formIntersection(prs.map(\.key))
        return fresh
    }
}

/// Where `QueueState` and the team list live between launches.
public protocol KeyValueStore: AnyObject {
    func stringArray(forKey: String) -> [String]?
    func array(forKey: String) -> [Any]?
    func set(_ value: Any?, forKey: String)
}

extension UserDefaults: KeyValueStore {}

public struct Persistence {
    let store: KeyValueStore
    public init(_ store: KeyValueStore = UserDefaults.standard) { self.store = store }

    public func loadState() -> QueueState {
        var s = QueueState()
        s.dismissed = Set(store.stringArray(forKey: "dismissed") ?? [])
        s.muted = Set(store.stringArray(forKey: "muted") ?? [])
        s.seen = (store.array(forKey: "seen") as? [String]).map(Set.init)
        s.notified = store.stringArray(forKey: "notified") ?? []
        return s
    }

    public func save(_ s: QueueState) {
        store.set(Array(s.dismissed).sorted(), forKey: "dismissed")
        store.set(Array(s.muted).sorted(), forKey: "muted")
        store.set(s.seen.map { Array($0).sorted() }, forKey: "seen")
        store.set(s.notified, forKey: "notified")
    }

    public func loadTeam() -> [String] { store.stringArray(forKey: "team") ?? [] }
    public func saveTeam(_ team: [String]) { store.set(team, forKey: "team") }
}

/// Normalises what someone typed into the "add teammate" field.
public func cleanLogin(_ raw: String) -> String {
    raw.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
}
