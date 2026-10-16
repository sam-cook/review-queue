import Foundation
import Testing
@testable import ReviewQueueCore

private func classify(_ n: Node) -> PR? { Classifier.classify(n.json, viewer: Node.me) }

@Suite("Someone else's PR")
struct OthersPRTests {
    @Test func unreviewedTeammatePR() {
        let pr = classify(Node())
        #expect(pr?.reason == .notReviewed)
        #expect(pr?.activity == Node.t0)
        #expect(pr?.repo == "acme/app")
        #expect(pr?.ci == .success)
    }

    @Test func closedAndDraftPRsAreHidden() {
        var closed = Node(); closed.state = "MERGED"
        var draft = Node(); draft.isDraft = true
        #expect(classify(closed) == nil)
        #expect(classify(draft) == nil)
    }

    @Test func directReviewRequest() {
        var n = Node(); n.requested = [Node.me]
        #expect(classify(n)?.reason == .reviewRequested)
    }

    @Test func reRequestAfterMyReview() {
        var n = Node(); n.requested = [Node.me]; n.review(Node.me, "COMMENTED", 10)
        #expect(classify(n)?.reason == .reReviewRequested)
    }

    @Test func iApprovedSoItIsHidden() {
        var n = Node(); n.review(Node.me, "APPROVED", 10); n.push(20)
        #expect(classify(n) == nil)
    }

    @Test func approvedBySomeoneElseAndIWasNeverInvolved() {
        var n = Node(); n.review("bob", "APPROVED", 10)
        #expect(classify(n) == nil)
    }

    @Test func approvedBySomeoneElseButIAmInvolved() {
        var n = Node(); n.review(Node.me, "COMMENTED", 5); n.review("bob", "APPROVED", 10); n.push(20)
        let pr = classify(n)
        #expect(pr?.reason == .newCommits)
        #expect(pr?.othersApproved == true)
    }

    @Test func botApprovalDoesNotCount() {
        var n = Node(); n.review("review-bot", "APPROVED", 10, bot: true)
        let pr = classify(n)
        #expect(pr?.reason == .notReviewed)
        #expect(pr?.othersApproved == false)
    }

    @Test func newCommitsAfterMyReview() {
        var n = Node(); n.review(Node.me, "CHANGES_REQUESTED", 10); n.push(5); n.push(30)
        let pr = classify(n)
        #expect(pr?.reason == .newCommits)
        #expect(pr?.activity == Node.at(30))
    }

    @Test func forcePushCountsAsNewCommits() {
        var n = Node(); n.review(Node.me, "COMMENTED", 10); n.forcePush(20)
        #expect(classify(n)?.reason == .newCommits)
    }

    @Test func authorRepliedAfterMyReview() {
        var n = Node(); n.review(Node.me, "COMMENTED", 10); n.comment("alice", 20)
        #expect(classify(n)?.reason == .authorReplied)
    }

    @Test func someoneElsesCommentIsNotAReply() {
        var n = Node(); n.review(Node.me, "COMMENTED", 10); n.comment("carol", 20)
        #expect(classify(n)?.reason == .waitingOnAuthor)
    }

    @Test func myPlainCommentCountsAsInvolvement() {
        var n = Node(); n.comment(Node.me, 10)
        #expect(classify(n)?.reason == .waitingOnAuthor)
        n.push(20)
        #expect(classify(n)?.reason == .newCommits)
    }

    @Test func dismissedReviewNeedsAReReview() {
        var n = Node(); n.review(Node.me, "DISMISSED", 10)
        #expect(classify(n)?.reason == .reReviewRequested)
    }

    @Test func changesRequestedBySomeoneElseIsNotMyTurn() {
        var n = Node(); n.push(5); n.review("bob", "CHANGES_REQUESTED", 10)
        #expect(classify(n)?.reason == .waitingOnOthers)
        n.push(20)  // the author addressed it
        #expect(classify(n)?.reason == .notReviewed)
    }

    @Test func pendingReviewsAreIgnored() {
        var n = Node(); n.review(Node.me, "PENDING", 10)
        #expect(classify(n)?.reason == .notReviewed)
    }

    @Test func countsMyUnresolvedThreads() {
        var n = Node(); n.review(Node.me, "COMMENTED", 10)
        n.thread(starter: Node.me, last: "alice", 11)
        n.thread(starter: Node.me, last: Node.me, 12)
        n.thread(resolved: true, starter: Node.me, last: Node.me, 13)
        n.thread(starter: "bob", last: "bob", 14)
        #expect(classify(n)?.myOpenThreads == 2)
    }
}

@Suite("My own PR")
struct MyPRTests {
    func mine() -> Node { var n = Node(); n.author = Node.me; return n }

    @Test func noFeedbackIsHidden() {
        #expect(classify(mine()) == nil)
    }

    @Test func myDraftsStillShowFeedback() {
        var n = mine(); n.isDraft = true; n.review("bob", "CHANGES_REQUESTED", 10)
        #expect(classify(n)?.reason == .changesRequested)
    }

    @Test func changesRequestedAfterMyLastPush() {
        var n = mine(); n.push(5); n.review("bob", "CHANGES_REQUESTED", 10)
        #expect(classify(n)?.reason == .changesRequested)
    }

    @Test func pushingAddressesChangeRequests() {
        var n = mine(); n.review("bob", "CHANGES_REQUESTED", 10); n.push(20)
        #expect(classify(n) == nil)
    }

    @Test func unresolvedThreadsWhereTheLastReplyIsNotMine() {
        var n = mine()
        n.thread(starter: "bob", last: "bob", 10)
        n.thread(starter: "bob", last: Node.me, 11)  // I answered: not waiting on me
        n.thread(starter: "carol", last: "carol", 12)
        let pr = classify(n)
        #expect(pr?.reason == .unresolvedThreads)
        #expect(pr?.unresolved == 2)
        #expect(pr?.label == "2 unresolved")
    }

    @Test func reviewerCommentAfterMyLastActivity() {
        var n = mine(); n.requested = ["bob"]; n.push(5); n.comment("bob", 10)
        #expect(classify(n)?.reason == .newComments)
        n.comment(Node.me, 20)  // I answered
        #expect(classify(n) == nil)
    }

    @Test func commentsFromNonReviewersAreIgnored() {
        var n = mine(); n.comment("ci-status-service", 10)
        #expect(classify(n) == nil)
    }

    @Test func botChangeRequestsAreIgnored() {
        var n = mine(); n.review("lint-bot", "CHANGES_REQUESTED", 10, bot: true)
        #expect(classify(n) == nil)
    }
}

@Suite("Parsing")
struct ParsingTests {
    @Test func missingFieldsAreSkippedNotCrashed() {
        #expect(Classifier.classify([:], viewer: "me") == nil)
        #expect(Classifier.classify(["number": 1, "title": "x"], viewer: "me") == nil)
    }

    @Test func fractionalSecondsParse() {
        #expect(Classifier.date("2026-10-15T13:02:15.123Z") != nil)
        #expect(Classifier.date("2026-10-15T13:02:15Z") != nil)
        #expect(Classifier.date("yesterday") == nil)
    }

    @Test func unknownCIStateIsNil() {
        var n = Node(); n.ci = "SOMETHING_NEW"
        #expect(classify(n)?.ci == nil)
    }
}
