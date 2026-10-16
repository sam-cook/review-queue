import Foundation

/// Why a PR is in the list. Lower raw values are more urgent.
public enum Reason: Int, Comparable, CaseIterable, Sendable {
    // On someone else's PR
    case reviewRequested, reReviewRequested, newCommits, authorReplied, notReviewed
    // On the viewer's own PR
    case changesRequested, unresolvedThreads, newComments
    // Not the viewer's turn
    case waitingOnAuthor, waitingOnOthers

    public static func < (a: Reason, b: Reason) -> Bool { a.rawValue < b.rawValue }

    /// The viewer should act now (as opposed to "Waiting").
    public var needsMe: Bool { self < .waitingOnAuthor }
    /// It is about the viewer's own PR.
    public var onMine: Bool { [.changesRequested, .unresolvedThreads, .newComments].contains(self) }

    public var label: String {
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

    /// A UI-independent colour family; the app maps it to real colours.
    public enum Tone: Sendable { case request, commits, reply, warning, neutral }

    public var tone: Tone {
        switch self {
        case .reviewRequested, .reReviewRequested: return .request
        case .newCommits: return .commits
        case .authorReplied, .newComments: return .reply
        case .changesRequested, .unresolvedThreads: return .warning
        default: return .neutral
        }
    }
}

/// Combined status of a PR's latest commit, as GitHub reports it.
public enum CIStatus: String, Sendable {
    case success = "SUCCESS", failure = "FAILURE", error = "ERROR", pending = "PENDING", expected = "EXPECTED"

    public enum Summary: Sendable { case passed, failed, running, none }

    public static func summary(_ s: CIStatus?) -> Summary {
        switch s {
        case .success: return .passed
        case .failure, .error: return .failed
        case .pending, .expected: return .running
        case nil: return .none
        }
    }
}

/// One PR as the queue shows it.
public struct PR: Sendable, Equatable {
    public let number: Int
    public let title: String
    public let url: URL
    public let repo: String  // owner/name
    public let author: String
    public let avatar: URL?
    public let created: Date
    public let ci: CIStatus?
    public let reason: Reason
    public let activity: Date  // latest event behind `reason`
    public var unresolved = 0  // open review threads waiting on the author (own PRs)
    public var othersApproved = false  // another person approved; it may merge soon
    public var myOpenThreads = 0  // unresolved threads the viewer started on someone else's PR

    public init(number: Int, title: String, url: URL, repo: String, author: String, avatar: URL?, created: Date,
                ci: CIStatus?, reason: Reason, activity: Date) {
        self.number = number
        self.title = title
        self.url = url
        self.repo = repo
        self.author = author
        self.avatar = avatar
        self.created = created
        self.ci = ci
        self.reason = reason
        self.activity = activity
    }

    public var isMine: Bool { reason.onMine }
    public var label: String { reason == .unresolvedThreads ? "\(unresolved) unresolved" : reason.label }

    /// Changes whenever the PR needs the viewer again, so "seen" and "dismissed" reset by themselves.
    public var key: String { "\(url.absoluteString)|\(reason.rawValue)|\(Int(activity.timeIntervalSince1970))" }

    /// Queue order: most urgent reason first, then most recent activity.
    public static func queueOrder(_ a: PR, _ b: PR) -> Bool {
        a.reason != b.reason ? a.reason < b.reason : a.activity > b.activity
    }
}
