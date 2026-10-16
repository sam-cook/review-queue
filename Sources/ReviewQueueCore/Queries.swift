import Foundation

/// The single GraphQL request behind a refresh: up to five searches that share one fragment.
public enum Queries {
    static let fragment = """
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

    /// Each search's alias, and why it is there.
    public enum Search: String, CaseIterable, Sendable {
        case team  // teammates' recent PRs
        case reviewed  // PRs I reviewed, any author, any age
        case commented  // PRs I commented on
        case requested  // direct review requests
        case mine  // my own PRs
    }

    /// Page size per search. Keeps a refresh at about 210 GraphQL points.
    public static let pageSize = 40

    /// The query text and its variables. An empty team leaves the team search out entirely:
    /// GitHub does not treat a contradiction such as "author:@me -author:@me" as empty.
    public static func refresh(team: [String], windowDays: Int, now: Date = Date(),
                               calendar: Calendar = .current) -> (query: String, variables: [String: String]) {
        let since = calendar.date(byAdding: .day, value: -windowDays, to: now)!
        let day = ISO8601DateFormatter.string(from: since, timeZone: calendar.timeZone, formatOptions: [.withFullDate])
        let open = "is:pr is:open -is:draft"
        var vars: [String: String] = [
            "reviewed": "\(open) reviewed-by:@me",
            "commented": "\(open) commenter:@me -author:@me",
            "requested": "\(open) user-review-requested:@me",
            "mine": "is:pr is:open author:@me",
        ]
        let authors = team.map { "author:\(sanitize($0))" }.filter { $0 != "author:" }
        if !authors.isEmpty { vars["team"] = "\(open) created:>=\(day) \(authors.joined(separator: " "))" }

        let searches = Search.allCases.filter { vars[$0.rawValue] != nil }
        let decls = searches.map { "$\($0.rawValue): String!" }.joined(separator: ", ")
        let body = searches.map {
            "  \($0.rawValue): search(query: $\($0.rawValue), type: ISSUE, first: \(pageSize)) { nodes { ...F } }"
        }.joined(separator: "\n")
        return (fragment + "\nquery(\(decls)) {\n  viewer { login }\n\(body)\n}", vars)
    }

    /// GitHub logins are letters, digits and hyphens. Anything else would change the search.
    static func sanitize(_ login: String) -> String {
        String(login.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" })
    }
}
