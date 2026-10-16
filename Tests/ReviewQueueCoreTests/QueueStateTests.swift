import Foundation
import Testing
@testable import ReviewQueueCore

private func pr(_ n: Int, _ reason: Reason = .notReviewed, at minutes: Double = 0) -> PR {
    PR(number: n, title: "PR \(n)", url: URL(string: "https://github.com/acme/app/pull/\(n)")!, repo: "acme/app",
       author: "alice", avatar: nil, created: Node.t0, ci: nil, reason: reason, activity: Node.at(minutes))
}

@Suite("Queue state")
struct QueueStateTests {
    @Test func firstRefreshAnnouncesNothing() {
        var s = QueueState()
        #expect(s.applyRefresh([pr(1), pr(2)]).isEmpty)
        #expect(s.unseen([pr(1), pr(2)]).isEmpty)
    }

    @Test func newPRsAreAnnouncedOnce() {
        var s = QueueState()
        _ = s.applyRefresh([pr(1)])
        #expect(s.applyRefresh([pr(1), pr(2)]).map(\.number) == [2])
        #expect(s.applyRefresh([pr(1), pr(2)]).isEmpty)
        #expect(s.unseen([pr(1), pr(2)]) == [pr(2).key])
    }

    @Test func waitingPRsAreNeverAnnounced() {
        var s = QueueState()
        _ = s.applyRefresh([])
        #expect(s.applyRefresh([pr(1, .waitingOnAuthor)]).isEmpty)
    }

    @Test func dismissLastsUntilThePRChanges() {
        var s = QueueState()
        let before = pr(1, .notReviewed, at: 0)
        s.dismiss(before)
        _ = s.applyRefresh([before])
        #expect(s.isHidden(before))
        #expect(s.needsMe([before]).isEmpty)
        let after = pr(1, .newCommits, at: 30)  // something changed: new key
        _ = s.applyRefresh([after])
        #expect(!s.isHidden(after))
        #expect(s.dismissed.isEmpty, "the old dismissal is dropped")
    }

    @Test func muteIsForever() {
        var s = QueueState()
        s.mute(pr(1))
        #expect(s.isHidden(pr(1, .newCommits, at: 99)))
        s.restore(pr(1))
        #expect(!s.isHidden(pr(1)))
    }

    @Test func openingThePanelMarksEverythingSeen() {
        var s = QueueState()
        _ = s.applyRefresh([])
        _ = s.applyRefresh([pr(1), pr(2)])
        s.markSeen([pr(1), pr(2)])
        #expect(s.unseen([pr(1), pr(2)]).isEmpty)
    }

    @Test func notifiedHistoryIsCapped() {
        var s = QueueState()
        _ = s.applyRefresh([])
        _ = s.applyRefresh((1...(QueueState.notifiedLimit + 50)).map { pr($0) })
        #expect(s.notified.count == QueueState.notifiedLimit)
    }

    @Test func persistenceRoundTrip() {
        let store = MemoryStore()
        let p = Persistence(store)
        var s = QueueState()
        s.dismiss(pr(1)); s.mute(pr(2)); s.markSeen([pr(3)]); s.notified = ["a", "b"]
        p.save(s)
        #expect(p.loadState() == s)
        p.saveTeam(["alice", "bob"])
        #expect(p.loadTeam() == ["alice", "bob"])
    }

    @Test func freshInstallHasNoSeenSet() {
        #expect(Persistence(MemoryStore()).loadState().seen == nil)
    }

    @Test func queueOrderIsUrgencyThenRecency() {
        let sorted = [pr(1, .waitingOnAuthor, at: 50), pr(2, .newCommits, at: 10), pr(3, .newCommits, at: 20),
                      pr(4, .reviewRequested, at: 0)].sorted(by: PR.queueOrder)
        #expect(sorted.map(\.number) == [4, 3, 2, 1])
    }

    @Test func cleanLoginStripsAtAndSpaces() {
        #expect(cleanLogin("  @octocat ") == "octocat")
    }
}

final class MemoryStore: KeyValueStore {
    var values: [String: Any] = [:]
    func stringArray(forKey k: String) -> [String]? { values[k] as? [String] }
    func array(forKey k: String) -> [Any]? { values[k] as? [Any] }
    func set(_ value: Any?, forKey k: String) { values[k] = value }
}
