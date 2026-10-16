import Foundation

/// Decides whether a PR needs the viewer, and why. Pure: the input is one PR node from the
/// GraphQL query in `Queries`, so every rule can be tested with a JSON fixture.
public enum Classifier {
    /// Returns nil when the PR should not be shown.
    public static func classify(_ n: [String: Any], viewer me: String) -> PR? {
        guard let number = n["number"] as? Int, let title = n["title"] as? String,
              let url = (n["url"] as? String).flatMap(URL.init(string:)),
              let author = (n["author"] as? [String: Any])?["login"] as? String,
              let repo = (n["repository"] as? [String: Any])?["nameWithOwner"] as? String,
              let created = date(n["createdAt"])
        else { return nil }
        // Search results can lag behind; drop PRs that are already merged or closed.
        guard (n["state"] as? String) == "OPEN" else { return nil }
        let isDraft = (n["isDraft"] as? Bool) ?? false
        if isDraft && author != me { return nil }

        let requested = nodes(n, "reviewRequests").contains {
            (($0["requestedReviewer"] as? [String: Any])?["login"] as? String) == me
        }
        let reviews = nodes(n, "latestReviews").filter { ($0["state"] as? String) != "PENDING" }
        let timeline = nodes(n, "timelineItems")
        // My last involvement: a formal review, or a plain PR comment (treated like a "commented" review).
        let myComment = timeline.filter { $0["__typename"] as? String == "IssueComment" && login($0) == me }
            .compactMap { date($0["createdAt"]) }.max()
        var mine = reviews.first { login($0) == me }
        if mine == nil, let myComment {
            mine = ["state": "COMMENTED", "submittedAt": ISO8601DateFormatter().string(from: myComment)]
        }
        let myState = mine?["state"] as? String
        let myTime = [date(mine?["submittedAt"]), myComment].compactMap { $0 }.max()
        // Bot approvals (GitHub Apps, review bots) do not count.
        let humans = reviews.filter { (($0["author"] as? [String: Any])?["__typename"] as? String) != "Bot" }
        let othersApproved = humans.contains { ($0["state"] as? String) == "APPROVED" && login($0) != me }

        // Timeline: when the author pushed, and when the author replied.
        var pushes: [Date] = [], replies: [Date] = []
        for t in timeline {
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
        let commit = nodes(n, "commits").first?["commit"] as? [String: Any]
        let ci = ((commit?["statusCheckRollup"] as? [String: Any])?["state"] as? String).flatMap(CIStatus.init(rawValue:))
        let avatar = ((n["author"] as? [String: Any])?["avatarUrl"] as? String).flatMap(URL.init(string:))
        func make(_ reason: Reason, _ activity: Date) -> PR {
            PR(number: number, title: title, url: url, repo: repo, author: author, avatar: avatar,
               created: created, ci: ci, reason: reason, activity: activity)
        }

        if author == me {
            // My PR: has anyone given feedback I have not addressed?
            // Only reviewers' comments count; this skips service accounts that post status comments.
            let reviewers = Set(humans.compactMap(login) + nodes(n, "reviewRequests").compactMap {
                ($0["requestedReviewer"] as? [String: Any])?["login"] as? String
            }).subtracting([me])
            var myLast = lastPush, othersComments: [Date] = []
            for t in timeline where t["__typename"] as? String == "IssueComment" {
                guard let d = date(t["createdAt"]), let who = login(t) else { continue }
                if who == me { myLast = max(myLast, d) } else if reviewers.contains(who) { othersComments.append(d) }
            }
            var openThreads: [Date] = []
            for th in nodes(n, "reviewThreads") where (th["isResolved"] as? Bool) == false {
                let last = ((th["last"] as? [String: Any])?["nodes"] as? [[String: Any]])?.last
                if let last, login(last) != me { openThreads.append(date(last["createdAt"]) ?? created) }
            }
            let changeRequests = humans.filter { ($0["state"] as? String) == "CHANGES_REQUESTED" && login($0) != me }
                .compactMap { date($0["submittedAt"]) }.filter { $0 > lastPush }

            var pr: PR
            if let d = changeRequests.max() { pr = make(.changesRequested, d) }
            else if let d = openThreads.max() { pr = make(.unresolvedThreads, d) }
            else if let d = othersComments.filter({ $0 > myLast }).max() { pr = make(.newComments, d) }
            else { return nil }
            pr.unresolved = openThreads.count
            return pr
        }

        var pr: PR
        if requested {
            pr = make(mine == nil ? .reviewRequested : .reReviewRequested, max(lastPush, myTime ?? created))
        } else if myState == "APPROVED" || (othersApproved && mine == nil) {
            return nil  // I approved, or someone else covered a review I was never part of
        } else if let myTime, myState != "DISMISSED" {
            if let p = pushes.filter({ $0 > myTime }).max() { pr = make(.newCommits, p) }
            else if let r = replies.filter({ $0 > myTime }).max() { pr = make(.authorReplied, r) }
            else { pr = make(.waitingOnAuthor, myTime) }
        } else if mine != nil {
            pr = make(.reReviewRequested, lastPush)  // my review was dismissed
        } else {
            // Someone else asked for changes and the author has not pushed since: not my turn yet.
            let blocking = humans.filter { ($0["state"] as? String) == "CHANGES_REQUESTED" }
                .compactMap { date($0["submittedAt"]) }.max()
            if let blocking, lastPush <= blocking { pr = make(.waitingOnOthers, blocking) }
            else { pr = make(.notReviewed, created) }
        }
        pr.othersApproved = othersApproved
        pr.myOpenThreads = nodes(n, "reviewThreads").filter { th in
            (th["isResolved"] as? Bool) == false
                && ((th["first"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first.flatMap(login) == me
        }.count
        return pr
    }

    // MARK: Helpers

    static func nodes(_ n: [String: Any], _ k: String) -> [[String: Any]] {
        (n[k] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
    }

    static func login(_ x: [String: Any]) -> String? {
        (x["author"] as? [String: Any])?["login"] as? String
    }

    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
