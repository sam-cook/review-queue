import Foundation

/// Builds a GraphQL PR node in the shape `Queries.fragment` returns, for readable rule tests.
struct Node {
    static let me = "me"
    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    var number = 1
    var author = "alice"
    var authorIsBot = false
    var state = "OPEN"
    var isDraft = false
    var created = t0
    var requested: [String] = []
    var reviews: [(who: String, state: String, at: Date, bot: Bool)] = []
    var threads: [(resolved: Bool, starter: String, last: String, at: Date)] = []
    var timeline: [[String: Any]] = []
    var ci: String? = "SUCCESS"

    static func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
    static func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

    mutating func review(_ who: String, _ state: String, _ minutes: Double, bot: Bool = false) {
        reviews.append((who, state, Node.at(minutes), bot))
    }

    mutating func comment(_ who: String, _ minutes: Double) {
        timeline.append(["__typename": "IssueComment", "createdAt": Node.iso(Node.at(minutes)),
                         "author": ["__typename": "User", "login": who]])
    }

    mutating func push(_ minutes: Double) {
        timeline.append(["__typename": "PullRequestCommit", "commit": ["committedDate": Node.iso(Node.at(minutes))]])
    }

    mutating func forcePush(_ minutes: Double) {
        timeline.append(["__typename": "HeadRefForcePushedEvent", "createdAt": Node.iso(Node.at(minutes))])
    }

    mutating func thread(resolved: Bool = false, starter: String, last: String, _ minutes: Double) {
        threads.append((resolved, starter, last, Node.at(minutes)))
    }

    var json: [String: Any] {
        var tl = timeline
        // The timeline also lists formal reviews, as GitHub does.
        for r in reviews { tl.append(["__typename": "PullRequestReview", "submittedAt": Node.iso(r.at), "author": ["login": r.who]]) }
        return [
            "number": number, "title": "PR \(number)", "url": "https://github.com/acme/app/pull/\(number)",
            "state": state, "isDraft": isDraft, "createdAt": Node.iso(created),
            "author": ["login": author, "avatarUrl": "https://avatars.githubusercontent.com/u/1"],
            "repository": ["nameWithOwner": "acme/app"],
            "reviewRequests": ["nodes": requested.map { ["requestedReviewer": ["login": $0]] }],
            "latestReviews": ["nodes": reviews.map {
                ["state": $0.state, "submittedAt": Node.iso($0.at), "author": ["__typename": $0.bot ? "Bot" : "User", "login": $0.who]]
            }],
            "reviewThreads": ["nodes": threads.map {
                ["isResolved": $0.resolved,
                 "first": ["nodes": [["author": ["login": $0.starter]]]],
                 "last": ["nodes": [["author": ["login": $0.last], "createdAt": Node.iso($0.at)]]]]
            }],
            "commits": ["nodes": [["commit": ["statusCheckRollup": ci.map { ["state": $0] } as Any]]]],
            "timelineItems": ["nodes": tl],
        ]
    }
}
