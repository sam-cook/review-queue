import Foundation
import ReviewQueueCore

/// Made-up PRs for `--demo` and README screenshots. No network, no account needed.
enum Demo {
    static func prs(now: Date = Date()) -> [PR] {
        func ago(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }
        func pr(_ n: Int, _ title: String, _ repo: String, _ author: String, _ reason: Reason, _ created: Double,
                _ activity: Double, ci: CIStatus? = .success) -> PR {
            PR(number: n, title: title, url: URL(string: "https://github.com/\(repo)/pull/\(n)")!, repo: repo,
               author: author, avatar: nil, created: ago(created), ci: ci, reason: reason, activity: ago(activity))
        }
        var approved = pr(318, "Cache parsed config between runs", "acme/build-tools", "mira", .newCommits, 30, 1)
        approved.othersApproved = true
        approved.myOpenThreads = 2
        var mine = pr(77, "Add retry with jitter to the uploader", "acme/uploader", "you", .unresolvedThreads, 20, 2, ci: .pending)
        mine.unresolved = 3
        return [
            pr(1204, "Migrate settings screen to the new form components", "acme/web", "jonas", .reviewRequested, 3, 0.5),
            approved,
            pr(91, "Fix flaky timeout in the payments integration test", "acme/payments", "aiko", .authorReplied, 50, 4),
            pr(552, "Document the release checklist", "acme/handbook", "sol", .notReviewed, 26, 26, ci: nil),
            mine,
            pr(640, "Drop support for the v1 webhooks", "acme/api", "dev", .waitingOnAuthor, 72, 24, ci: .failure),
        ]
    }
}
