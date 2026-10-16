import Foundation
import Testing
@testable import ReviewQueueCore

/// Serves canned responses instead of the network, and records requests.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, [String: String], Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream {  // URLSession moves bodies into a stream
            stream.open(); defer { stream.close() }
            var data = Data(), buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            req.httpBody = data
        }
        StubProtocol.requests.append(req)
        let (code, headers, body) = StubProtocol.handler?(req) ?? (500, [:], Data())
        let resp = HTTPURLResponse(url: req.url!, statusCode: code, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func fixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Tests share the stub's static state, so they run one at a time.
@Suite("GitHub client", .serialized)
struct GitHubClientTests {
    func client(host: String = "github.com", token: String? = "t0ken") -> GitHubClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        StubProtocol.requests = []
        return GitHubClient(settings: Settings(host: host), session: URLSession(configuration: config)) { token }
    }

    @Test func fetchesClassifiesDedupsAndSorts() async throws {
        let body = try fixture("refresh")
        StubProtocol.handler = { _ in (200, [:], body) }
        let (viewer, prs, warning) = try await client().fetchQueue(team: ["alice"])
        #expect(viewer == "me")
        #expect(warning == nil)
        // #1 is in two searches but listed once; #3 is closed; #2 asked me for a review.
        #expect(prs.map(\.number) == [2, 1])
        #expect(prs.first?.reason == .reviewRequested)

        let req = try #require(StubProtocol.requests.first)
        #expect(req.url?.absoluteString == "https://api.github.com/graphql")
        #expect(req.value(forHTTPHeaderField: "Authorization") == "bearer t0ken")
        let sent = try #require(try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any])
        #expect((sent["variables"] as? [String: String])?["team"]?.contains("author:alice") == true)
    }

    @Test func noTokenFailsWithoutARequest() async {
        await #expect(throws: GitHubError.noToken(host: "github.com")) { try await client(token: nil).fetchQueue(team: []) }
        #expect(StubProtocol.requests.isEmpty)
    }

    @Test func graphQLRateLimit() async {
        StubProtocol.handler = { _ in (200, [:], Data(#"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#.utf8)) }
        await #expect(throws: GitHubError.rateLimited) { try await client().fetchQueue(team: []) }
    }

    @Test func secondaryRateLimits() async {
        StubProtocol.handler = { _ in (403, ["retry-after": "60"], Data()) }
        await #expect(throws: GitHubError.rateLimited) { try await client().fetchQueue(team: []) }
        StubProtocol.handler = { _ in (429, [:], Data()) }
        await #expect(throws: GitHubError.rateLimited) { try await client().fetchQueue(team: []) }
    }

    @Test func badTokenAndServerErrors() async {
        StubProtocol.handler = { _ in (401, [:], Data()) }
        await #expect(throws: GitHubError.unauthorized) { try await client().fetchQueue(team: []) }
        StubProtocol.handler = { _ in (502, [:], Data("<html>".utf8)) }
        await #expect(throws: GitHubError.http(502)) { try await client().fetchQueue(team: []) }
        StubProtocol.handler = { _ in (200, [:], Data("not json".utf8)) }
        await #expect(throws: GitHubError.badResponse) { try await client().fetchQueue(team: []) }
    }

    @Test func graphQLErrorWithoutData() async {
        StubProtocol.handler = { _ in (200, [:], Data(#"{"data":null,"errors":[{"message":"Something broke"}]}"#.utf8)) }
        await #expect(throws: GitHubError.api("Something broke")) { try await client().fetchQueue(team: []) }
    }

    @Test func partialDataIsKeptWithAWarning() async throws {
        StubProtocol.handler = { _ in
            (200, [:], Data(#"{"data":{"viewer":{"login":"me"},"mine":{"nodes":[]}},"errors":[{"message":"Search timed out"}]}"#.utf8))
        }
        let (viewer, prs, warning) = try await client().fetchQueue(team: [])
        #expect(viewer == "me" && prs.isEmpty)
        #expect(warning == "Some results are missing: Search timed out")
    }

    @Test func lookupUser() async throws {
        StubProtocol.handler = { req in
            req.url!.path.hasSuffix("/users/octocat") ? (200, [:], Data(#"{"login":"Octocat"}"#.utf8)) : (404, [:], Data())
        }
        #expect(try await client().lookupUser("@octocat") == "Octocat")
        #expect(StubProtocol.requests.last?.url?.absoluteString == "https://api.github.com/users/octocat")
        #expect(try await client().lookupUser("nobody") == nil)
        #expect(try await client().lookupUser("!!!") == nil)
    }

    @Test func enterpriseUsesItsOwnAPI() async throws {
        StubProtocol.handler = { _ in (200, [:], Data(#"{"login":"alice"}"#.utf8)) }
        _ = try await client(host: "github.example.com").lookupUser("alice")
        #expect(StubProtocol.requests.last?.url?.absoluteString == "https://github.example.com/api/v3/users/alice")
    }

    @Test func avatarsNeverGetTheTokenOnGitHubDotCom() async {
        StubProtocol.handler = { _ in (200, [:], Data([1, 2, 3])) }
        let data = await client().avatar(URL(string: "https://avatars.githubusercontent.com/u/1")!)
        #expect(data == Data([1, 2, 3]))
        #expect(StubProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
        _ = await client(host: "github.example.com").avatar(URL(string: "https://github.example.com/alice.png")!)
        #expect(StubProtocol.requests.last?.value(forHTTPHeaderField: "Authorization") == "token t0ken")
    }
}
