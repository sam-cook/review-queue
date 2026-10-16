import Foundation

/// Where to find GitHub, and how often to look. Read once at launch.
public struct Settings: Sendable, Equatable {
    /// `github.com`, or a GitHub Enterprise Server host such as `github.example.com`.
    public var host: String
    /// How far back to look for teammates' PRs that nobody has reviewed yet.
    public var windowDays: Int
    /// Seconds between refreshes. github.com allows 5,000 GraphQL points an hour; a refresh costs at most ~210.
    public var refreshInterval: TimeInterval

    public static let defaultHost = "github.com"
    public static let minimumRefreshInterval: TimeInterval = 60

    public init(host: String = Settings.defaultHost, windowDays: Int = 7, refreshInterval: TimeInterval = 5 * 60) {
        // Accept "github.example.com", "https://github.example.com/", or a URL with a path.
        let raw = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = URLComponents(string: raw.contains("://") ? raw : "https://\(raw)")
        let h = (c?.host ?? "") + (c?.port.map { ":\($0)" } ?? "")
        self.host = h.isEmpty ? Settings.defaultHost : h.lowercased()
        self.windowDays = max(1, windowDays)
        self.refreshInterval = max(Settings.minimumRefreshInterval, refreshInterval)
    }

    /// Reads the optional overrides `host`, `windowDays` and `refreshInterval` from user defaults.
    public init(defaults: UserDefaults) {
        self.init(
            host: defaults.string(forKey: "host") ?? Settings.defaultHost,
            windowDays: Settings.number(defaults.object(forKey: "windowDays")).map(Int.init) ?? 7,
            refreshInterval: Settings.number(defaults.object(forKey: "refreshInterval")) ?? 5 * 60)
    }

    /// `defaults write` stores a string unless given `-int`; accept both.
    static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// The settings domain. Fixed, so a development build reads the same settings as the app.
    public static let domain = "io.github.sam-cook.review-queue"

    public var isGitHubDotCom: Bool { host == "github.com" }

    public var graphqlURL: URL {
        URL(string: isGitHubDotCom ? "https://api.github.com/graphql" : "https://\(host)/api/graphql")!
    }

    public var restBase: URL {
        URL(string: isGitHubDotCom ? "https://api.github.com" : "https://\(host)/api/v3")!
    }

    /// A user's avatar by login. github.com redirects to its avatar CDN.
    public func avatarURL(for login: String) -> URL? {
        URL(string: "https://\(host)/\(login).png?size=64")
    }

    /// Only an Enterprise host's own avatar URLs need the token; never send it anywhere else.
    public func avatarNeedsToken(_ url: URL) -> Bool {
        !isGitHubDotCom && (url.host?.lowercased() ?? "") + (url.port.map { ":\($0)" } ?? "") == host
    }
}
