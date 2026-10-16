import Foundation
import Testing
@testable import ReviewQueueCore

@Suite("Queries")
struct QueriesTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15
    var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test func teamSearchUsesTheWindow() {
        let (q, v) = Queries.refresh(team: ["alice", "bob"], windowDays: 7, now: now, calendar: utc)
        #expect(v["team"] == "is:pr is:open -is:draft created:>=2027-01-08 author:alice author:bob")
        #expect(q.contains("team: search(query: $team"))
        #expect(q.contains("$team: String!"))
    }

    @Test func emptyTeamLeavesTheSearchOut() {
        let (q, v) = Queries.refresh(team: [], windowDays: 7, now: now)
        #expect(v["team"] == nil)
        #expect(!q.contains("$team"))
        #expect(q.contains("$reviewed: String!") && q.contains("mine: search"))
    }

    @Test func everyDeclaredVariableIsUsedAndSet() {
        for team in [[], ["alice"]] {
            let (q, v) = Queries.refresh(team: team, windowDays: 7, now: now)
            for key in v.keys {
                #expect(q.contains("$\(key): String!"), "declared: \(key)")
                #expect(q.contains("query: $\(key),"), "used: \(key)")
            }
        }
    }

    @Test func loginsCannotInjectSearchSyntax() {
        let (_, v) = Queries.refresh(team: ["alice is:closed", "  ", "bob-2"], windowDays: 7, now: now)
        #expect(v["team"]?.hasSuffix("author:aliceisclosed author:bob-2") == true)
    }
}

@Suite("Settings")
struct SettingsTests {
    @Test func githubDotComEndpoints() {
        let s = Settings()
        #expect(s.isGitHubDotCom)
        #expect(s.graphqlURL.absoluteString == "https://api.github.com/graphql")
        #expect(s.restBase.absoluteString == "https://api.github.com")
    }

    @Test func enterpriseEndpoints() {
        let s = Settings(host: "https://GitHub.Example.com/")
        #expect(s.host == "github.example.com")
        #expect(s.graphqlURL.absoluteString == "https://github.example.com/api/graphql")
        #expect(s.restBase.absoluteString == "https://github.example.com/api/v3")
    }

    @Test func tokenOnlyGoesToTheEnterpriseHost() {
        let ghe = Settings(host: "github.example.com")
        #expect(ghe.avatarNeedsToken(URL(string: "https://github.example.com/alice.png")!))
        #expect(!ghe.avatarNeedsToken(URL(string: "https://evil.example.net/alice.png")!))
        #expect(!Settings().avatarNeedsToken(URL(string: "https://github.com/alice.png")!))
    }

    @Test func hostAcceptsURLs() {
        #expect(Settings(host: "http://github.example.com/some/path").host == "github.example.com")
        #expect(Settings(host: "GitHub.Example.com").host == "github.example.com")
        let port = Settings(host: "github.example.com:8443")
        #expect(port.host == "github.example.com:8443")
        #expect(port.graphqlURL.absoluteString == "https://github.example.com:8443/api/graphql")
        #expect(port.avatarNeedsToken(URL(string: "https://github.example.com:8443/a.png")!))
        #expect(!port.avatarNeedsToken(URL(string: "https://github.example.com/a.png")!))
    }

    @Test func numbersWrittenAsStringsAreAccepted() {
        let d = UserDefaults(suiteName: "review-queue-tests-\(UUID())")!
        d.set("14", forKey: "windowDays")
        d.set("600", forKey: "refreshInterval")
        let s = Settings(defaults: d)
        #expect(s.windowDays == 14 && s.refreshInterval == 600)
    }

    @Test func limitsAreEnforced() {
        let s = Settings(host: "", windowDays: 0, refreshInterval: 5)
        #expect(s.host == "github.com")
        #expect(s.windowDays == 1)
        #expect(s.refreshInterval == Settings.minimumRefreshInterval)
    }

    @Test func readsUserDefaults() {
        let d = UserDefaults(suiteName: "review-queue-tests-\(UUID())")!
        d.set("ghe.example.org", forKey: "host")
        d.set(3, forKey: "windowDays")
        d.set(120.0, forKey: "refreshInterval")
        #expect(Settings(defaults: d) == Settings(host: "ghe.example.org", windowDays: 3, refreshInterval: 120))
    }

    @Test func environmentTokenWins() {
        #expect(Credentials.token(host: "github.com", environment: ["GH_TOKEN": " abc \n"]) == "abc")
        #expect(Credentials.token(host: "github.example.com", environment: ["GH_ENTERPRISE_TOKEN": "ent"]) == "ent")
    }

    @Test func githubDotComTokenNeverGoesToEnterprise() {
        // With no enterprise token, it falls through to gh (absent from this PATH-less test: nil or gh's own answer),
        // but never the github.com token.
        let t = Credentials.token(host: "github.example.com", environment: ["GH_TOKEN": "dotcom-token"])
        #expect(t != "dotcom-token")
    }
}
