import Foundation
import Testing
@testable import TGArchive

@Suite("API client")
struct APIClientTests {
    private func client(_ server: MockServer, cookie: String? = nil) -> APIClient {
        APIClient(server: server.address, cookie: cookie, configuration: MockServer.configuration(),
                  cache: MockServer.cache())
    }

    @Test("Status codes and error bodies map to APIError",
          arguments: [
              (400, #"{"detail": "Invalid before_date format. Use ISO 8601."}"#,
               APIError.badRequest(detail: "Invalid before_date format. Use ISO 8601.")),
              (401, #"{"detail": "Unauthorized"}"#, .unauthorized),
              (403, #"{"detail": "Downloads disabled for this account"}"#,
               .forbidden(detail: "Downloads disabled for this account")),
              (404, #"{"detail": "Chat not found"}"#, .notFound),
              (422, #"{"detail": [{"loc": ["query", "limit"], "msg": "too big"}]}"#, .badRequest(detail: nil)),
              (429, #"{"detail": "Too many login attempts"}"#, .rateLimited),
              (500, #"{"detail": "Database not available"}"#, .serverUnavailable(detail: "Database not available")),
              (500, #"{"detail": "Internal server error"}"#, .server(status: 500, detail: "Internal server error")),
              (502, "<html>Bad gateway</html>", .server(status: 502, detail: nil)),
              (503, #"{"detail": "Viewer authentication is not configured"}"#,
               .serverUnavailable(detail: "Viewer authentication is not configured")),
          ])
    func statusMapping(_ status: Int, _ body: String, _ expected: APIError) async {
        let server = MockServer { _ in .json(body, status: status) }
        await #expect(throws: expected) { let _: Health = try await client(server).get(.health) }
    }

    @Test("The committed 401, 403 and 404 bodies map to their cases",
          arguments: [("error-401", 401, APIError.unauthorized),
                      ("error-403", 403, .forbidden(detail: "Downloads disabled for this account")),
                      ("error-404", 404, .notFound),
                      ("login-401", 401, .unauthorized)])
    func fixtureErrors(_ fixture: String, _ status: Int, _ expected: APIError) async throws {
        let response = try MockServer.Response.fixture(fixture, status: status)
        let server = MockServer { _ in response }
        await #expect(throws: expected) { let _: ChatsPage = try await client(server).get(.chats()) }
    }

    @Test("A transport failure maps to .transport with its code",
          arguments: [URLError.Code.notConnectedToInternet, .timedOut, .appTransportSecurityRequiresSecureConnection])
    func transport(_ code: URLError.Code) async {
        let server = MockServer { _ in .transportFailure(code) }
        await #expect(throws: APIError.transport(code)) { let _: Health = try await client(server).get(.health) }
    }

    @Test("A 2xx body that does not decode is .decoding")
    func decodingFailure() async {
        let server = MockServer { _ in .json("<html></html>") }
        do {
            let _: AuthCheck = try await client(server).get(.authCheck)
            Issue.record("expected a decoding error")
        } catch {
            guard case .decoding = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
        }
    }

    @Test("Every request carries the session cookie as an explicit header, and no other cookie")
    func cookieHeader() async throws {
        let response = try MockServer.Response.fixture("chats")
        let server = MockServer { _ in response }
        let page: ChatsPage = try await client(server, cookie: "abc123").get(.chats())
        #expect(page.chats.count == 14)
        _ = try await client(server, cookie: "abc123").data(for: .avatar(ref: "r1"))
        let anonymous: ChatsPage = try await client(server).get(.chats())
        #expect(anonymous.chats.count == 14)

        let cookies = server.requests.map(\.cookie)
        #expect(cookies == ["viewer_auth=abc123", "viewer_auth=abc123", nil])
        #expect(HTTPCookieStorage.shared.cookies(for: server.address.baseURL)?.isEmpty ?? true)
    }

    @Test("Set-Cookie from a login answer is captured with its expiry, over https and plain http",
          arguments: [true, false])
    func setCookieCaptured(_ secure: Bool) async throws {
        let server = MockServer { _ in
            .json(#"{"success": true, "role": "viewer", "username": "family"}"#, headers: [
                "Set-Cookie": "viewer_auth=sess-\(secure ? "s" : "p"); expires=Fri, 06 Nov 2026 14:00:00 GMT; "
                    + "HttpOnly; Max-Age=2592000; Path=/; SameSite=lax\(secure ? "; Secure" : "")",
            ])
        }
        let (value, cookie): (LoginResponse, HTTPCookie?) = try await client(server)
            .post(.login, body: LoginBody(username: "family", password: "pw"))
        #expect(value.username == "family")
        let captured = try #require(cookie)
        #expect(captured.value == "sess-\(secure ? "s" : "p")")
        #expect(captured.expiresDate != nil)
        #expect(captured.isSecure == secure)

        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/login")
        #expect(request.headers["Content-Type"] == "application/json")
        let body = try JSONSerialization.jsonObject(with: try #require(request.body)) as? [String: String]
        #expect(body == ["username": "family", "password": "pw"])
        #expect(HTTPCookieStorage.shared.cookies(for: server.address.baseURL)?.isEmpty ?? true)
    }

    @Test("A login answer without the session cookie gives no cookie")
    func noSetCookie() async throws {
        let server = MockServer { _ in .json(#"{"success": true, "message": "Anonymous access"}"#,
                                             headers: ["Set-Cookie": "other=1; Path=/"]) }
        let (_, cookie): (LoginResponse, HTTPCookie?) = try await client(server)
            .post(.login, body: LoginBody(username: "a", password: "b"))
        #expect(cookie == nil)
    }

    @Test("The messages route's bare array decodes as a page")
    func messagesArray() async throws {
        let response = try MockServer.Response.fixture("messages-weekend-hikers")
        let server = MockServer { _ in response }
        let page: MessagePage = try await client(server, cookie: "c").get(.messages(ref: "abc"))
        #expect(page.messages.count == 50)
        #expect(server.requests.first?.query == ["limit": "50"])
    }

    @Test("Query parameters for chats, messages and search",
          arguments: [
              (Endpoint.chats(), "/api/chats", ["limit": "50", "offset": "0", "archived": "false"]),
              (.chats(limit: 20, offset: 40, search: "book club", archived: true, folderID: 3), "/api/chats",
               ["limit": "20", "offset": "40", "search": "book club", "archived": "true", "folder_id": "3"]),
              (.chats(search: "", archived: nil), "/api/chats", ["limit": "50", "offset": "0"]),
              (.messages(ref: "R", limit: 50, cursor: .beforeID(1273), topicID: 39), "/api/chats/R/messages",
               ["limit": "50", "before_id": "1273", "topic_id": "39"]),
              (.messages(ref: "R", cursor: .after(id: 900)), "/api/chats/R/messages",
               ["limit": "50", "after_id": "900"]),
              (.messages(ref: "R", cursor: .before(date: Date(timeIntervalSince1970: 1_791_380_880), id: 1275)),
               "/api/chats/R/messages", ["limit": "50", "before_date": "2026-10-07T13:48:00Z", "before_id": "1275"]),
              (.search(query: "C++ & co", limit: 20, offset: 40), "/api/search/messages",
               ["q": "C++ & co", "limit": "20", "offset": "40"]),
          ])
    func queries(_ endpoint: Endpoint, _ path: String, _ query: [String: String]) throws {
        let url = endpoint.url(base: URL(string: "https://example.com")!)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == path)
        var items: [String: String] = [:]
        for item in components.queryItems ?? [] { items[item.name] = item.value }
        #expect(items == query)
        #expect(!(components.percentEncodedQuery ?? "").contains("+"))
    }

    @Test("Paths, methods, cache policies and the sign-out timeout")
    func requestShape() {
        let base = URL(string: "http://127.0.0.1:8000")!
        let cases: [(Endpoint, String, String)] = [
            (.health, "GET", "/api/health"),
            (.authCheck, "GET", "/api/auth/check"),
            (.login, "POST", "/api/login"),
            (.tokenLogin, "POST", "/auth/token"),
            (.logout, "POST", "/api/logout"),
            (.chat(ref: "R"), "GET", "/api/chats/R"),
            (.folders, "GET", "/api/folders"),
            (.archivedCount, "GET", "/api/archived/count"),
            (.topics(ref: "R"), "GET", "/api/chats/R/topics"),
            (.stats, "GET", "/api/stats"),
            (.media(ref: "R", key: "7_video_note"), "GET", "/media/R/7_video_note"),
            (.thumbnail(size: .small, ref: "R", key: "1274_photo"), "GET", "/media/thumb/200/R/1274_photo"),
            (.avatar(ref: "R"), "GET", "/media/avatar/R"),
            (.senderAvatar(ref: "R", messageID: 1274), "GET", "/media/avatar/R/1274"),
        ]
        for (endpoint, method, path) in cases {
            let request = endpoint.request(base: base)
            #expect(request.httpMethod == method)
            #expect(request.url?.path() == path)
            #expect(request.cachePolicy == (endpoint.isMedia ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData))
            #expect(request.timeoutInterval == (endpoint == .logout ? 5 : 30))
        }
        #expect(Endpoint.chat(ref: "a/b?c").url(base: base).path(percentEncoded: true) == "/api/chats/a%2Fb%3Fc")
    }

    @Test("Every string key exists in both English and Spanish")
    func localizations() throws {
        func keys(_ language: String) throws -> Set<String> {
            let url = try #require(Bundle.main.url(forResource: "Localizable", withExtension: "strings",
                                                   subdirectory: nil, localization: language))
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            return Set(table.keys)
        }
        let english = try keys("en")
        let spanish = try keys("es")
        #expect(english == spanish)

        let errors: [APIError] = [.unauthorized, .forbidden(detail: nil), .notFound, .rateLimited,
                                  .badRequest(detail: nil), .serverUnavailable(detail: nil),
                                  .serverUnavailable(detail: "Viewer authentication is not configured"),
                                  .server(status: 502, detail: nil), .notAnArchiveServer,
                                  .transport(.appTransportSecurityRequiresSecureConnection), .transport(.cancelled),
                                  .transport(.timedOut), .transport(.serverCertificateUntrusted),
                                  .transport(.notConnectedToInternet), .decoding("x")]
        let sessionErrors: [SessionError] = [.invalidAddress, .setupRequired, .proxyAuthUnsupported, .busy,
                                             .noServer]
        for message in errors.map(\.message) + sessionErrors.map(\.message) {
            #expect(!message.hasPrefix("api.error") && !message.hasPrefix("session.error"), "untranslated: \(message)")
        }
        #expect(APIError.server(status: 502, detail: nil).message.contains("502"))
    }
}
