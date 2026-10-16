import Foundation

public enum GitHubError: LocalizedError, Equatable {
    case noToken(host: String)
    case rateLimited
    case unauthorized
    case http(Int)
    case api(String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .noToken(let host):
            return host == Settings.defaultHost
                ? "No GitHub token. Run: gh auth login"
                : "No GitHub token. Run: gh auth login --hostname \(host)"
        case .rateLimited: return "GitHub rate limit reached"
        case .unauthorized: return "GitHub rejected the token. Run: gh auth refresh"
        case .http(let code): return "GitHub returned HTTP \(code)"
        case .api(let m): return m
        case .badResponse: return "Bad response from GitHub"
        }
    }
}

/// Talks to the GitHub GraphQL and REST APIs. Reads only; never comments, approves or changes anything.
/// Sendable: every stored property is an immutable `let` of a thread-safe type.
public final class GitHubClient: @unchecked Sendable {
    public let settings: Settings
    private let token: @Sendable () -> String?
    private let session: URLSession

    /// `token` is called for every request, so a fresh `gh auth login` takes effect at once.
    public init(settings: Settings, session: URLSession = .shared, token: @escaping @Sendable () -> String?) {
        self.settings = settings
        self.session = session
        self.token = token
    }

    /// One refresh: every PR that needs the viewer (or is waiting on someone else), deduplicated and sorted.
    /// `warning` is set when GitHub answered only some of the searches, so the list may be incomplete.
    public func fetchQueue(team: [String], now: Date = Date()) async throws -> (viewer: String, prs: [PR], warning: String?) {
        let (query, vars) = Queries.refresh(team: team, windowDays: settings.windowDays, now: now)
        let (data, warning) = try await graphQL(query: query, variables: vars)
        guard let me = (data["viewer"] as? [String: Any])?["login"] as? String else { throw GitHubError.badResponse }
        var byURL: [URL: PR] = [:]
        for search in Queries.Search.allCases {
            let nodes = (data[search.rawValue] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
            for n in nodes { if let pr = Classifier.classify(n, viewer: me) { byURL[pr.url] = pr } }
        }
        return (me, byURL.values.sorted(by: PR.queueOrder), warning)
    }

    /// The login with its real casing, or nil when no such user exists.
    public func lookupUser(_ name: String) async throws -> String? {
        let clean = Queries.sanitize(name)
        guard !clean.isEmpty else { return nil }
        let (data, code) = try await send(URLRequest(url: settings.restBase.appendingPathComponent("users/\(clean)")))
        if code == 404 { return nil }
        try check(code)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["login"] as? String
    }

    /// Downloads an avatar. The token goes only to an Enterprise host's own URLs.
    public func avatar(_ url: URL) async -> Data? {
        var req = URLRequest(url: url)
        if settings.avatarNeedsToken(url), let t = token() { req.setValue("token \(t)", forHTTPHeaderField: "Authorization") }
        guard let (data, resp) = try? await session.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    // MARK: Transport

    func graphQL(query: String, variables: [String: String]) async throws -> (data: [String: Any], warning: String?) {
        var req = URLRequest(url: settings.graphqlURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, code) = try await send(req)
        try check(code)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GitHubError.badResponse }
        var warning: String?
        if let errors = json["errors"] as? [[String: Any]], let first = errors.first {
            if (first["type"] as? String) == "RATE_LIMITED" { throw GitHubError.rateLimited }
            let m = first["message"] as? String ?? "GitHub error"
            if m.localizedCaseInsensitiveContains("rate limit") { throw GitHubError.rateLimited }
            // Partial data is still useful when only some searches failed.
            if json["data"] == nil || json["data"] is NSNull { throw GitHubError.api(m) }
            warning = "Some results are missing: \(m)"
        }
        guard let d = json["data"] as? [String: Any] else { throw GitHubError.badResponse }
        return (d, warning)
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let t = token() else { throw GitHubError.noToken(host: settings.host) }
        var req = request
        req.setValue("bearer \(t)", forHTTPHeaderField: "Authorization")
        req.setValue("ReviewQueue", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        // Secondary rate limits come back as 403 or 429 with these headers.
        if http?.statusCode == 429 || (http?.statusCode == 403
            && (http?.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0" || http?.value(forHTTPHeaderField: "retry-after") != nil)) {
            throw GitHubError.rateLimited
        }
        return (data, http?.statusCode ?? 0)
    }

    private func check(_ code: Int) throws {
        switch code {
        case 200: return
        case 401: throw GitHubError.unauthorized
        default: throw GitHubError.http(code)
        }
    }
}
