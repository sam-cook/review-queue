// Review Queue — a menu bar app showing which teammates' PRs need your review now, on GitHub.
import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

// MARK: - Config

/// github.com by default. For GitHub Enterprise Server: `defaults write io.github.sam-cook.review-queue host <your-ghe-host>`
let host = UserDefaults.standard.string(forKey: "host") ?? "github.com"
let apiBase = host == "github.com" ? "https://api.github.com" : "https://\(host)/api/v3"
let graphqlURL = URL(string: host == "github.com" ? "https://api.github.com/graphql" : "https://\(host)/api/graphql")!
let windowDays = 7
/// github.com allows 5,000 GraphQL points an hour; a refresh costs about 210.
let refreshInterval: TimeInterval = 5 * 60

// MARK: - Model

/// Why a PR is in the list. Lower raw values are more urgent.
enum Reason: Int, Comparable {
    case reviewRequested, reReviewRequested, newCommits, authorReplied, notReviewed
    case changesRequested, unresolvedThreads, newComments  // on the viewer's own PRs
    case waitingOnAuthor, waitingOnOthers

    static func < (a: Reason, b: Reason) -> Bool { a.rawValue < b.rawValue }

    var needsMe: Bool { self < .waitingOnAuthor }
    var onMine: Bool { [.changesRequested, .unresolvedThreads, .newComments].contains(self) }

    var label: String {
        switch self {
        case .reviewRequested: return "Review requested"
        case .reReviewRequested: return "Re-review requested"
        case .newCommits: return "New commits"
        case .authorReplied: return "Author replied"
        case .notReviewed: return "Not reviewed"
        case .changesRequested: return "Changes requested"
        case .unresolvedThreads: return "Unresolved threads"
        case .newComments: return "New comments"
        case .waitingOnAuthor: return "Waiting on author"
        case .waitingOnOthers: return "Changes requested"
        }
    }

    var color: Color {
        switch self {
        case .reviewRequested, .reReviewRequested: return .blue
        case .newCommits: return .purple
        case .authorReplied, .newComments: return .teal
        case .changesRequested, .unresolvedThreads: return .orange
        default: return .secondary
        }
    }
}

struct PR {
    let number: Int
    let title: String
    let url: URL
    let repo: String
    let author: String
    let avatar: URL?
    let created: Date
    let ci: String?
    let reason: Reason
    let activity: Date  // latest event behind `reason`
    var unresolved = 0  // open review threads waiting on the author
    var othersApproved = false  // another person approved; it may merge soon
    var myOpenThreads = 0  // unresolved threads I started on someone else's PR

    var isMine: Bool { reason.onMine }
    var label: String { reason == .unresolvedThreads ? "\(unresolved) unresolved" : reason.label }

    /// Changes when the PR needs the viewer again, so the badge lights up again.
    var key: String { "\(url.absoluteString)|\(reason.rawValue)|\(Int(activity.timeIntervalSince1970))" }
}

enum FetchError: LocalizedError {
    case noToken, api(String)
    var errorDescription: String? {
        switch self {
        case .noToken: return "No GitHub token. Run: gh auth login --hostname \(host)"
        case .api(let m): return m
        }
    }
}

// MARK: - GitHub

enum GitHub {
    static let fields = """
    fragment F on PullRequest {
      number title url state isDraft createdAt
      author { login avatarUrl(size: 64) }
      repository { nameWithOwner }
      reviewRequests(first: 10) { nodes { requestedReviewer { ... on User { login } } } }
      latestReviews(first: 20) { nodes { state submittedAt author { __typename login } } }
      reviewThreads(first: 50) { nodes { isResolved
        first: comments(first: 1) { nodes { author { login } } }
        last: comments(last: 1) { nodes { author { login } createdAt } } } }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      timelineItems(last: 40, itemTypes: [ISSUE_COMMENT, PULL_REQUEST_REVIEW, PULL_REQUEST_COMMIT, HEAD_REF_FORCE_PUSHED_EVENT]) {
        nodes {
          __typename
          ... on IssueComment { createdAt author { __typename login } }
          ... on PullRequestReview { submittedAt author { login } }
          ... on PullRequestCommit { commit { committedDate } }
          ... on HeadRefForcePushedEvent { createdAt }
        }
      }
    }
    """

    /// Page sizes keep one refresh at ~210 GraphQL points (github.com limit: 5,000/hour, shared with other tools).
    /// Five searches, merged: teammates' recent PRs, PRs I reviewed or commented on (any author, any age),
    /// direct review requests, and my PRs.
    static let query = fields + """
    query($team: String!, $reviewed: String!, $commented: String!, $requested: String!, $mine: String!) {
      viewer { login }
      team: search(query: $team, type: ISSUE, first: 40) { nodes { ...F } }
      reviewed: search(query: $reviewed, type: ISSUE, first: 40) { nodes { ...F } }
      commented: search(query: $commented, type: ISSUE, first: 40) { nodes { ...F } }
      requested: search(query: $requested, type: ISSUE, first: 40) { nodes { ...F } }
      mine: search(query: $mine, type: ISSUE, first: 40) { nodes { ...F } }
    }
    """

    /// Reads the token from the gh CLI so the app needs no separate login.
    static func token() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["gh", "auth", "token", "--hostname", host]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        let t = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return p.terminationStatus == 0 && !t.isEmpty ? t : nil
    }

    static func fetch(team: [String], completion: @escaping (Result<[PR], Error>) -> Void) {
        DispatchQueue.global().async {
            guard let token = token() else { return completion(.failure(FetchError.noToken)) }
            let since = Calendar.current.date(byAdding: .day, value: -windowDays, to: Date())!
            let day = ISO8601DateFormatter.string(from: since, timeZone: .current, formatOptions: [.withFullDate])
            let open = "is:pr is:open -is:draft"
            let authors = team.map { "author:\($0)" }.joined(separator: " ")
            let vars = [
                "team": "\(open) created:>=\(day) \(authors)",
                "reviewed": "\(open) reviewed-by:@me",
                "commented": "\(open) commenter:@me -author:@me",
                "requested": "\(open) user-review-requested:@me",
                "mine": "is:pr is:open author:@me",
            ]

            var req = URLRequest(url: graphqlURL)
            req.httpMethod = "POST"
            req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
            // No team: leave the search out. GitHub does not treat "author:@me -author:@me" as empty.
            var q = query, v = vars
            if team.isEmpty {
                q = q.replacingOccurrences(of: "$team: String!, ", with: "")
                    .replacingOccurrences(of: "  team: search(query: $team, type: ISSUE, first: 40) { nodes { ...F } }\n", with: "")
                v["team"] = nil
            }
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["query": q, "variables": v])

            URLSession.shared.dataTask(with: req) { data, _, err in
                if let err { return completion(.failure(err)) }
                guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return completion(.failure(FetchError.api("Bad response from GitHub")))
                }
                if let errors = json["errors"] as? [[String: Any]], let m = errors.first?["message"] as? String {
                    return completion(.failure(FetchError.api(m)))
                }
                let d = json["data"] as? [String: Any] ?? [:]
                guard let me = (d["viewer"] as? [String: Any])?["login"] as? String else {
                    return completion(.failure(FetchError.api("Could not read your GitHub login")))
                }
                var byURL: [URL: PR] = [:]
                for key in ["team", "reviewed", "commented", "requested", "mine"] {
                    let nodes = (d[key] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
                    for n in nodes { if let pr = parse(n, me: me) { byURL[pr.url] = pr } }
                }
                completion(.success(Array(byURL.values)))
            }.resume()
        }
    }

    /// Checks that a GitHub user exists; returns the login with its real casing.
    static func lookupUser(_ name: String, completion: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            guard let token = token(),
                  let url = URL(string: "\(apiBase)/users/\(name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)")
            else { return completion(nil) }
            var req = URLRequest(url: url)
            req.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { data, resp, _ in
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                completion((resp as? HTTPURLResponse)?.statusCode == 200 ? json?["login"] as? String : nil)
            }.resume()
        }
    }

    static func date(_ v: Any?) -> Date? { (v as? String).flatMap { ISO8601DateFormatter().date(from: $0) } }

    /// Decides whether and why the PR needs the viewer (`me`). Returns nil to hide it.
    static func parse(_ n: [String: Any], me: String) -> PR? {
        guard let number = n["number"] as? Int, let title = n["title"] as? String,
              let url = (n["url"] as? String).flatMap(URL.init),
              let author = (n["author"] as? [String: Any])?["login"] as? String,
              let repo = (n["repository"] as? [String: Any])?["nameWithOwner"] as? String,
              let created = date(n["createdAt"])
        else { return nil }
        // Search results can lag behind; drop PRs that are already merged or closed.
        guard (n["state"] as? String) == "OPEN" else { return nil }
        let isDraft = (n["isDraft"] as? Bool) ?? false
        if isDraft && author != me { return nil }

        func nodes(_ k: String) -> [[String: Any]] { (n[k] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [] }
        func login(_ x: [String: Any]) -> String? { (x["author"] as? [String: Any])?["login"] as? String }

        let requested = nodes("reviewRequests").contains {
            (($0["requestedReviewer"] as? [String: Any])?["login"] as? String) == me
        }
        let reviews = nodes("latestReviews").filter { ($0["state"] as? String) != "PENDING" }
        // My last involvement: a formal review, or a plain PR comment (treated like a "commented" review).
        let myComment = nodes("timelineItems").filter { $0["__typename"] as? String == "IssueComment" && login($0) == me }
            .compactMap { date($0["createdAt"]) }.max()
        var mine = reviews.first { login($0) == me }
        if mine == nil, let myComment { mine = ["state": "COMMENTED", "submittedAt": ISO8601DateFormatter().string(from: myComment)] }
        let myState = mine?["state"] as? String
        let myTime = [date(mine?["submittedAt"]), myComment].compactMap { $0 }.max()
        // Bot approvals (e.g. review bots) do not count as approval.
        let humans = reviews.filter { (($0["author"] as? [String: Any])?["__typename"] as? String) != "Bot" }
        let othersApproved = humans.contains { ($0["state"] as? String) == "APPROVED" && login($0) != me }

        // Timeline: when the author pushed, and when the author replied.
        var pushes: [Date] = [], replies: [Date] = []
        for t in nodes("timelineItems") {
            switch t["__typename"] as? String {
            case "PullRequestCommit":
                if let d = date((t["commit"] as? [String: Any])?["committedDate"]) { pushes.append(d) }
            case "HeadRefForcePushedEvent":
                if let d = date(t["createdAt"]) { pushes.append(d) }
            case "IssueComment":
                if login(t) == author, let d = date(t["createdAt"]) { replies.append(d) }
            case "PullRequestReview":
                if login(t) == author, let d = date(t["submittedAt"]) { replies.append(d) }
            default: break
            }
        }
        let lastPush = pushes.max() ?? created
        let commit = nodes("commits").first?["commit"] as? [String: Any]
        let ci = (commit?["statusCheckRollup"] as? [String: Any])?["state"] as? String
        let avatar = ((n["author"] as? [String: Any])?["avatarUrl"] as? String).flatMap(URL.init)

        if author == me {
            // My PR: has anyone given feedback I have not addressed?
            // Only reviewers' comments count; this skips service accounts that post status comments.
            let reviewers = Set(humans.compactMap(login) + nodes("reviewRequests").compactMap {
                ($0["requestedReviewer"] as? [String: Any])?["login"] as? String
            }).subtracting([me])
            var myLast = lastPush, othersComments: [Date] = []
            for t in nodes("timelineItems") where t["__typename"] as? String == "IssueComment" {
                guard let d = date(t["createdAt"]), let who = login(t) else { continue }
                if who == me { myLast = max(myLast, d) } else if reviewers.contains(who) { othersComments.append(d) }
            }
            var openThreads: [Date] = []
            for th in nodes("reviewThreads") where (th["isResolved"] as? Bool) == false {
                let last = ((th["last"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last
                if let last, login(last) != me { openThreads.append(date(last["createdAt"]) ?? created) }
            }
            let changeRequests = humans.filter { ($0["state"] as? String) == "CHANGES_REQUESTED" && login($0) != me }
                .compactMap { date($0["submittedAt"]) }.filter { $0 > lastPush }

            let reason: Reason, activity: Date
            if let d = changeRequests.max() { reason = .changesRequested; activity = d }
            else if let d = openThreads.max() { reason = .unresolvedThreads; activity = d }
            else if let d = othersComments.filter({ $0 > myLast }).max() { reason = .newComments; activity = d }
            else { return nil }
            var pr = PR(number: number, title: title, url: url, repo: repo, author: author, avatar: avatar,
                        created: created, ci: ci, reason: reason, activity: activity)
            pr.unresolved = openThreads.count
            return pr
        }

        var reason: Reason
        var activity = created
        if requested {
            reason = mine == nil ? .reviewRequested : .reReviewRequested
            activity = max(lastPush, myTime ?? created)
        } else if myState == "APPROVED" || (othersApproved && mine == nil) {
            return nil  // I approved, or someone else covered a review I was never part of
        } else if let myTime, myState != "DISMISSED" {
            if let p = pushes.filter({ $0 > myTime }).max() {
                reason = .newCommits; activity = p
            } else if let r = replies.filter({ $0 > myTime }).max() {
                reason = .authorReplied; activity = r
            } else {
                reason = .waitingOnAuthor; activity = myTime
            }
        } else if mine != nil {
            reason = .reReviewRequested; activity = lastPush  // my review was dismissed
        } else {
            // Someone else asked for changes and the author has not pushed since: not my turn yet.
            let blocking = humans.filter { ($0["state"] as? String) == "CHANGES_REQUESTED" }.compactMap { date($0["submittedAt"]) }.max()
            if let blocking, lastPush <= blocking {
                reason = .waitingOnOthers; activity = blocking
            } else {
                reason = .notReviewed
            }
        }

        var pr = PR(number: number, title: title, url: url, repo: repo, author: author, avatar: avatar,
                    created: created, ci: ci, reason: reason, activity: activity)
        pr.othersApproved = othersApproved
        pr.myOpenThreads = nodes("reviewThreads").filter { th in
            (th["isResolved"] as? Bool) == false
                && ((th["first"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first.flatMap(login) == me
        }.count
        return pr
    }
}

// MARK: - Menu bar icon

enum Art {
    static let red = NSColor(srgbRed: 0.898, green: 0.325, blue: 0.294, alpha: 1)

    /// PR symbol with a round count badge. Template (follows the menu bar) unless highlighted.
    static func statusIcon(count: Int?, highlight: Bool) -> NSImage {
        let size = NSSize(width: count == nil ? 18 : 26, height: 18)
        let label = count.map { $0 > 99 ? "99+" : String($0) }
        let img = NSImage(size: size, flipped: false) { _ in
            let ctx = NSGraphicsContext.current!
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
        return img
    }
}

// MARK: - Store

final class Store: ObservableObject {
    @Published var prs: [PR] = []
    @Published var error: String?
    @Published var updated: Date?
    @Published var loading = false
    @Published var newKeys: Set<String> = []  // needed you since last open; highlighted while the panel is open
    @Published var avatars: [String: NSImage] = [:]
    @Published var icon = Art.statusIcon(count: 0, highlight: false)
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    @Published var team: [String] {
        didSet { UserDefaults.standard.set(team, forKey: "team"); refresh() }
    }

    private var timer: Timer?

    var seen: Set<String>? {
        get { (UserDefaults.standard.array(forKey: "seen") as? [String]).map(Set.init) }
        set { UserDefaults.standard.set(newValue.map { Array($0) }, forKey: "seen") }
    }

    /// Dismissed until the PR needs you for a new reason (stores PR keys).
    @Published var dismissed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "dismissed") ?? []) {
        didSet { UserDefaults.standard.set(Array(dismissed), forKey: "dismissed") }
    }
    /// Hidden for good (stores PR URLs).
    @Published var muted: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "muted") ?? []) {
        didSet { UserDefaults.standard.set(Array(muted), forKey: "muted") }
    }

    func isHidden(_ pr: PR) -> Bool { dismissed.contains(pr.key) || muted.contains(pr.url.absoluteString) }
    var visible: [PR] { prs.filter { !isHidden($0) } }
    var hidden: [PR] { prs.filter(isHidden) }
    var needsMe: [PR] { visible.filter { $0.reason.needsMe } }

    func dismiss(_ pr: PR) { dismissed.insert(pr.key); updateIcon() }
    func mute(_ pr: PR) { muted.insert(pr.url.absoluteString); updateIcon() }
    func restore(_ pr: PR) {
        dismissed.remove(pr.key)
        muted.remove(pr.url.absoluteString)
        updateIcon()
    }

    var unseen: Set<String> {
        let s = seen ?? []
        return Set(needsMe.map(\.key).filter { !s.contains($0) })
    }

    /// Keys already announced with a notification, so each event notifies once.
    var notified: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "notified") ?? []) }
        set { UserDefaults.standard.set(Array(newValue.suffix(500)), forKey: "notified") }
    }

    init(autoRefresh: Bool = true) {
        team = UserDefaults.standard.stringArray(forKey: "team") ?? []
        guard autoRefresh else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
    }

    private var refreshAgain = false
    private var pausedUntil: Date?  // set after hitting the GitHub rate limit

    func refresh(manual: Bool = false) {
        guard !loading else { refreshAgain = true; return }  // e.g. team changed mid-fetch
        if !manual, let p = pausedUntil, p > Date() { return }
        loading = true
        GitHub.fetch(team: team) { result in
            DispatchQueue.main.async {
                self.loading = false
                switch result {
                case .success(let prs):
                    self.prs = prs.sorted { ($0.reason, $1.activity) < ($1.reason, $0.activity) }
                    self.error = nil
                    self.updated = Date()
                    if self.seen == nil {  // first run: nothing is "new" yet
                        self.seen = Set(self.needsMe.map(\.key))
                        self.notified = Set(self.needsMe.map(\.key))
                    }
                    self.notify()
                    let live = Set(self.prs.map(\.key))
                    self.dismissed = self.dismissed.intersection(live)
                case .failure(let e):
                    self.error = e.localizedDescription
                    if e.localizedDescription.localizedCaseInsensitiveContains("rate limit") {
                        let until = Date().addingTimeInterval(10 * 60)
                        self.pausedUntil = until
                        self.error = "GitHub rate limit reached. Retrying at \(until.formatted(date: .omitted, time: .shortened))."
                    }
                }
                if self.error == nil { self.pausedUntil = nil }
                self.updateIcon()
                self.loadAvatars()
                if self.refreshAgain { self.refreshAgain = false; self.refresh() }
            }
        }
    }

    func updateIcon() {
        icon = error != nil && prs.isEmpty
            ? Art.statusIcon(count: nil, highlight: false)
            : Art.statusIcon(count: needsMe.count, highlight: !unseen.isEmpty)
    }

    func didOpen() {
        // Catch PRs closed or changed since the last timed refresh.
        if Date().timeIntervalSince(updated ?? .distantPast) > 60 { refresh() }
        newKeys = unseen
        seen = Set(needsMe.map(\.key))
        updateIcon()
    }

    func didClose() { newKeys = [] }

    /// Posts one macOS notification per new reason a PR needs you.
    func notify() {
        let fresh = needsMe.filter { !notified.contains($0.key) && !(seen ?? []).contains($0.key) }
        guard !fresh.isEmpty else { return }
        notified = notified.union(fresh.map(\.key))
        for pr in fresh.prefix(5) {
            let c = UNMutableNotificationContent()
            c.title = pr.isMine ? "Your PR · \(pr.label)" : "\(pr.label) · \(pr.author)"
            c.body = pr.title
            c.userInfo = ["url": pr.url.absoluteString]
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: pr.key, content: c, trigger: nil))
        }
    }

    /// Load avatars ourselves (cached in memory). GitHub Enterprise avatars need the token; github.com's must not get it.
    func loadAvatars() {
        var wanted = Dictionary(team.compactMap { u in URL(string: "https://\(host)/\(u).png?size=64").map { (u, $0) } },
                                uniquingKeysWith: { a, _ in a })
        for pr in prs { if let a = pr.avatar { wanted[pr.author] = a } }
        for (user, url) in wanted where avatars[user] == nil {
            DispatchQueue.global().async {
                var req = URLRequest(url: url)
                if host != "github.com", url.host == host, let t = GitHub.token() {
                    req.setValue("token \(t)", forHTTPHeaderField: "Authorization")
                }
                URLSession.shared.dataTask(with: req) { data, _, _ in
                    guard let data, let img = NSImage(data: data) else { return }
                    DispatchQueue.main.async { self.avatars[user] = img }
                }.resume()
            }
        }
    }

    /// Adds a teammate after checking the username exists. Calls back with an error message, or nil.
    func addMember(_ raw: String, completion: @escaping (String?) -> Void) {
        let name = raw.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !name.isEmpty else { return completion(nil) }
        if team.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return completion("Already in the team") }
        GitHub.lookupUser(name) { login in
            DispatchQueue.main.async {
                guard let login else { return completion("No user “\(name)” on \(host)") }
                self.team.append(login)
                completion(nil)
            }
        }
    }

    func removeMember(_ name: String) { team.removeAll { $0 == name } }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            self.error = "Launch at Login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Views

let dateFormat: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE d MMM · HH:mm"
    return f
}()

struct Panel: View {
    @ObservedObject var store: Store
    var snapshot = false  // ImageRenderer cannot draw a ScrollView
    @State private var editing = false

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
                        TeamEditor(store: store)
                    } else {
                        Section(title: "Needs your review", prs: store.needsMe.filter { !$0.isMine }, store: store,
                                empty: "You are all caught up")
                        Section(title: "Your PRs", prs: store.needsMe.filter(\.isMine), store: store)
                        Section(title: "Waiting", prs: store.visible.filter { !$0.reason.needsMe }, store: store,
                                collapsible: true)
                        Section(title: "Dismissed", prs: store.hidden, store: store, collapsible: true)
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
            Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
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

struct TeamEditor: View {
    @ObservedObject var store: Store
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
                TextField("GitHub username", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focused)
                    .onSubmit(add)
                    .disabled(checking)
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
        store.addMember(draft) { err in
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

struct Section: View {
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

    var ciColor: Color {
        switch pr.ci {
        case "SUCCESS": return .green
        case "FAILURE", "ERROR": return .red
        case "PENDING", "EXPECTED": return .orange
        default: return .secondary.opacity(0.4)
        }
    }

    var ciHelp: String {
        switch pr.ci {
        case "SUCCESS": return "Checks passed"
        case "FAILURE", "ERROR": return "Checks failed"
        case "PENDING", "EXPECTED": return "Checks running"
        default: return "No checks"
        }
    }

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
                        Pill(text: pr.label, color: pr.reason.color)
                        if pr.othersApproved { Pill(text: "Approved", color: .green).help("Approved by someone else; it may merge soon") }
                        if pr.myOpenThreads > 0 {
                            Pill(text: "\(pr.myOpenThreads) open", color: .secondary).help("Your unresolved review threads")
                        }
                        Circle().fill(ciColor).frame(width: 6, height: 6).help(ciHelp)
                        Text(verbatim: "\(pr.repo.split(separator: "/").last ?? "")#\(pr.number)")
                            .lineLimit(1).truncationMode(.middle)
                        Text("·").foregroundStyle(.quaternary)
                        Text(dateFormat.string(from: pr.created)).fixedSize()
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

// MARK: - App

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if let s = r.notification.request.content.userInfo["url"] as? String, let u = URL(string: s) {
            NSWorkspace.shared.open(u)
        }
        done()
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
let notificationDelegate = NotificationDelegate()

struct ReviewQueueApp: App {
    @StateObject var store = Store()
    init() { UNUserNotificationCenter.current().delegate = notificationDelegate }
    var body: some Scene {
        MenuBarExtra {
            Panel(store: store)
        } label: {
            Image(nsImage: store.icon)
        }
        .menuBarExtraStyle(.window)
    }
}

// `ReviewQueue --dump` prints the fetched PRs and exits (for testing without the UI).
let savedTeam = UserDefaults.standard.stringArray(forKey: "team") ?? []
if CommandLine.arguments.contains("--dump") {
    GitHub.fetch(team: savedTeam) { result in
        switch result {
        case .success(let prs): prs.sorted { $0.reason < $1.reason }.forEach {
            print($0.label.padding(toLength: 20, withPad: " ", startingAt: 0), $0.othersApproved ? "approved" : "        ",
                  "open:\($0.myOpenThreads)", $0.author, "\($0.repo)#\($0.number)", $0.title) }
        case .failure(let e): print("error:", e.localizedDescription)
        }
        exit(0)
    }
    dispatchMain()
}

// `ReviewQueue --snapshot out.png [dark]` renders the panel to an image (for design checks).
if let i = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let out = CommandLine.arguments[i + 1]
    let dark = CommandLine.arguments.contains("dark")
    _ = NSApplication.shared
    GitHub.fetch(team: savedTeam) { result in
        DispatchQueue.main.async {
            let store = Store(autoRefresh: false)
            store.prs = ((try? result.get()) ?? []).sorted { ($0.reason, $1.activity) < ($1.reason, $0.activity) }
            store.updated = Date()
            if let first = store.needsMe.first { store.newKeys = [first.key] }
            let view = Panel(store: store, snapshot: true)
                .background(dark ? Color(white: 0.16) : Color(white: 0.97))
                .environment(\.colorScheme, dark ? .dark : .light)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: out))
            }
            exit(0)
        }
    }
    RunLoop.main.run()
}

ReviewQueueApp.main()
