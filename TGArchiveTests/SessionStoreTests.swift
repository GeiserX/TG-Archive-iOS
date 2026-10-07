import Foundation
import Synchronization
import Testing
@testable import TGArchive

/// The Keychain's stand-in: one slot in memory.
final class MemoryVault: SessionVault {
    private let slot: Mutex<StoredSession?>

    init(_ session: StoredSession? = nil) { slot = Mutex(session) }

    var stored: StoredSession? { slot.withLock { $0 } }
    func load() throws -> StoredSession? { slot.withLock { $0 } }
    func save(_ session: StoredSession) throws { slot.withLock { $0 = session } }
    func delete() throws { slot.withLock { $0 = nil } }
}

/// Counts the runs of a wipe step.
@MainActor
final class Counter {
    var count = 0
}

@MainActor
@Suite("Session store")
struct SessionStoreTests {
    private let vault = MemoryVault()
    private let defaults: UserDefaults
    private let cache = MockServer.cache()

    init() {
        let suite = "tgarchive.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // Past the first launch, unless a test says otherwise.
        defaults.set(true, forKey: "installMarker")
    }

    private func store(now: Date = Date()) -> SessionStore {
        SessionStore(vault: vault, defaults: defaults, configuration: MockServer.configuration(), cache: cache,
                     now: { now })
    }

    private nonisolated static let cookieHeader = "viewer_auth=new-session; expires=Fri, 06 Nov 2026 14:00:00 GMT; HttpOnly; "
        + "Max-Age=2592000; Path=/; SameSite=lax"

    /// A server that signs anyone in with the cookie `new-session` and accepts any cookie but `revoked`.
    private nonisolated static func archive(role: String = "master", username: String = "admin",
                                noDownload: Bool = false) -> MockServer.Handler {
        { request in
            switch (request.method, request.path) {
            case ("GET", "/api/auth/check"):
                if let cookie = request.cookie, cookie.hasPrefix("viewer_auth="), cookie != "viewer_auth=revoked" {
                    return .json(#"{"authenticated": true, "auth_required": true, "role": "\#(role)", "#
                        + #""username": "\#(username)", "no_download": \#(noDownload)}"#)
                }
                return .json(#"{"authenticated": false, "auth_required": true}"#)
            case ("POST", "/api/login"), ("POST", "/auth/token"):
                return .json(#"{"success": true, "role": "\#(role)", "username": "\#(username)"}"#,
                             headers: ["Set-Cookie": cookieHeader])
            case ("POST", "/api/logout"):
                return .json(#"{"success": true}"#)
            default:
                return .json(#"{"detail": "Not Found"}"#, status: 404)
            }
        }
    }

    private func stored(_ server: MockServer, cookie: String? = "old-session", expires: Date? = nil,
                        role: StoredSession.Role = .viewer) -> StoredSession {
        StoredSession(server: server.address, cookie: cookie, cookieExpires: expires, username: "family",
                      role: role, noDownload: false)
    }

    private func readySession(_ store: SessionStore) throws -> Session {
        guard case let .ready(session) = store.phase else {
            throw TestFailure("expected .ready, got \(store.phase)")
        }
        return session
    }

    struct TestFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    // MARK: Connect

    @Test("Connect: a server that needs a login goes to sign-in, with a pasted link's token prefilled")
    func connectToSignIn() async throws {
        let server = MockServer(handler: Self.archive())
        let store = store()
        try await store.connect("\(server.address.baseURL.absoluteString)/#token=demo-share-link-not-a-secret")
        #expect(store.phase == .signIn(server.address, prefilledToken: "demo-share-link-not-a-secret", reason: nil))
        #expect(store.lastServer == server.address.baseURL.absoluteString)
        #expect(server.requests.map(\.path) == ["/api/auth/check"])
        #expect(server.requests.first?.cookie == nil)
    }

    @Test("Connect: an anonymous server opens at once with no session cookie")
    func connectAnonymous() async throws {
        let server = MockServer { _ in .json(#"{"authenticated": false, "auth_required": false}"#) }
        let store = store()
        try await store.connect(server.address.baseURL.absoluteString)
        let session = try readySession(store)
        #expect(session.stored.role == .anonymous)
        #expect(session.stored.cookie == nil)
        #expect(vault.stored == session.stored)
    }

    @Test("Connect: what is not an archive server, and the two unsupported setups",
          arguments: [
              (MockServer.Response.json("<!doctype html><html></html>"), SessionError.api(.notAnArchiveServer)),
              (.json(#"{"detail": "Not Found"}"#, status: 404), .api(.notAnArchiveServer)),
              (.json(#"{"status": "ok"}"#), .api(.notAnArchiveServer)),
              (.json(#"{"authenticated": false, "auth_required": true, "setup_required": true}"#), .setupRequired),
              (.json(#"{"authenticated": true, "auth_required": true, "proxy_auth": true}"#), .proxyAuthUnsupported),
              (.transportFailure(.cannotConnectToHost), .api(.transport(.cannotConnectToHost))),
          ])
    func connectFailures(_ response: MockServer.Response, _ expected: SessionError) async {
        let server = MockServer { _ in response }
        let store = store()
        await #expect(throws: expected) { try await store.connect(server.address.baseURL.absoluteString) }
        #expect(store.phase == .restoring)
        #expect(vault.stored == nil)
    }

    @Test("Connect: text that is no address makes no request")
    func connectInvalid() async {
        let store = store()
        await #expect(throws: SessionError.invalidAddress) { try await store.connect("not an address") }
    }

    // MARK: Sign in

    @Test("Sign-in with a password keeps the cookie from Set-Cookie and confirms it with the auth check")
    func signInPassword() async throws {
        let server = MockServer(handler: Self.archive(role: "viewer", username: "family", noDownload: true))
        let store = store()
        try await store.connect(server.address.baseURL.absoluteString)
        try await store.signIn(username: "family", password: "demo")

        let session = try readySession(store)
        #expect(session.stored.cookie == "new-session")
        #expect(session.stored.cookieExpires != nil)
        #expect(session.stored.role == .viewer)
        #expect(session.stored.username == "family")
        #expect(session.stored.noDownload)
        #expect(session.client.cookie == "new-session")
        #expect(vault.stored == session.stored)
        #expect(store.lastUsername == "family")
        #expect(!store.isSigningIn)

        #expect(server.requests.map(\.path) == ["/api/auth/check", "/api/login", "/api/auth/check"])
        #expect(server.requests.last?.cookie == "viewer_auth=new-session")
        let stored = String(decoding: try JSONEncoder().encode(session.stored), as: UTF8.self)
        #expect(!stored.contains("demo"), "the password must never be stored")
    }

    @Test("Sign-in with a share link sends the token exactly as given, even when it is not hex")
    func signInToken() async throws {
        let server = MockServer(handler: Self.archive(role: "token", username: "token:Hike photos", noDownload: true))
        let store = store()
        try await store.connect("\(server.address.baseURL.absoluteString)/#token=demo-share-link-not-a-secret")
        guard case let .signIn(_, token?, _) = store.phase else { throw TestFailure("no prefilled token") }
        try await store.signIn(token: token)

        let session = try readySession(store)
        #expect(session.stored.role == .token)
        #expect(session.stored.noDownload)
        let post = try #require(server.requests(to: "/auth/token").first)
        let body = try JSONSerialization.jsonObject(with: try #require(post.body)) as? [String: String]
        #expect(body == ["token": "demo-share-link-not-a-secret"])
    }

    @Test("Signing in while signed in ends the old server session first")
    func signInWhileSignedIn() async throws {
        let server = MockServer(handler: Self.archive())
        try vault.save(stored(server))
        let store = store()
        await store.restore()
        _ = try readySession(store)

        try await store.signIn(username: "admin", password: "pw")
        let paths = server.requests.map(\.path)
        #expect(paths == ["/api/auth/check", "/api/logout", "/api/login", "/api/auth/check"])
        #expect(server.requests[1].cookie == "viewer_auth=old-session")
        #expect(try readySession(store).stored.cookie == "new-session")
    }

    @Test("Wrong credentials: one request, the error, and no session")
    func wrongPassword() async throws {
        let server = MockServer { request in
            request.path == "/api/login"
                ? .json(#"{"detail": "Invalid credentials"}"#, status: 401)
                : .json(#"{"authenticated": false, "auth_required": true}"#)
        }
        let store = store()
        try await store.connect(server.address.baseURL.absoluteString)
        await #expect(throws: SessionError.wrongCredentials) {
            try await store.signIn(username: "admin", password: "wrong")
        }
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: nil))
        #expect(server.requests(to: "/api/login").count == 1)
        #expect(vault.stored == nil)
        #expect(SessionError.wrongCredentials.message != SessionError.api(.unauthorized).message)
    }

    @Test("A share link the server refuses is reported as a bad link, not as an ended session")
    func invalidLink() async throws {
        let server = MockServer { request in
            request.path == "/auth/token"
                ? .json(#"{"detail": "Invalid or expired token"}"#, status: 401)
                : .json(#"{"authenticated": false, "auth_required": true}"#)
        }
        let store = store()
        try await store.connect(server.address.baseURL.absoluteString)
        await #expect(throws: SessionError.invalidLink) { try await store.signIn(token: "revoked-link") }
        #expect(server.requests(to: "/auth/token").count == 1)
        #expect(vault.stored == nil)
        #expect(SessionError.invalidLink.message != SessionError.wrongCredentials.message)
    }

    @Test("Connecting to another server while signed in ends the old session there first")
    func connectWhileSignedIn() async throws {
        let old = MockServer(handler: Self.archive())
        let new = MockServer(handler: Self.archive())
        try vault.save(stored(old))
        let store = store()
        await store.restore()
        _ = try readySession(store)

        try await store.connect(new.address.baseURL.absoluteString)
        #expect(store.phase == .signIn(new.address, prefilledToken: nil, reason: nil))
        #expect(old.requests.map(\.path) == ["/api/auth/check", "/api/logout"])
        #expect(old.requests.last?.cookie == "viewer_auth=old-session")
        #expect(vault.stored == nil)
        #expect(new.requests.map(\.path) == ["/api/auth/check"])
    }

    @Test("A 429 is reported once and never retried")
    func rateLimitNeverRetries() async throws {
        let server = MockServer { request in
            request.path == "/auth/token"
                ? .json(#"{"detail": "Too many login attempts. Try again later."}"#, status: 429)
                : .json(#"{"authenticated": false, "auth_required": true}"#)
        }
        let store = store()
        try await store.connect(server.address.baseURL.absoluteString)
        await #expect(throws: SessionError.api(.rateLimited)) { try await store.signIn(token: "t") }
        #expect(server.requests(to: "/auth/token").count == 1)
        #expect(server.requests.count == 2)
        #expect(!store.isSigningIn)
    }

    @Test("Only one sign-in is ever in flight")
    func oneSignInAtATime() async throws {
        let handler = Self.archive()
        let server = MockServer { request in
            if request.path == "/api/login" { Thread.sleep(forTimeInterval: 0.3) }
            return handler(request)
        }
        let store = store()
        try await store.connect(server.address.baseURL.absoluteString)
        async let first: Void = store.signIn(username: "a", password: "b")
        async let second: Void = store.signIn(username: "a", password: "b")
        var failures: [SessionError] = []
        do { try await first } catch let error as SessionError { failures.append(error) }
        do { try await second } catch let error as SessionError { failures.append(error) }
        #expect(failures == [.busy])
        #expect(server.requests(to: "/api/login").count == 1)
    }

    @Test("A login answer with a message and no cookie means anonymous mode")
    func loginOnAnonymousServer() async throws {
        let server = MockServer { request in
            request.path == "/api/login"
                ? .json(#"{"success": true, "message": "Anonymous viewer access is enabled"}"#)
                : .json(#"{"authenticated": false, "auth_required": true}"#)
        }
        let store = store()
        try await store.connect(server.address.baseURL.absoluteString)
        try await store.signIn(username: "a", password: "b")
        #expect(try readySession(store).stored.role == .anonymous)
    }

    // MARK: Launch

    @Test("Launch with nothing stored shows connect")
    func restoreEmpty() async {
        let store = store()
        await store.restore()
        #expect(store.phase == .connect)
    }

    @Test("Launch with an expired session makes no network call")
    func restoreExpired() async throws {
        let server = MockServer(handler: Self.archive())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try vault.save(stored(server, expires: now.addingTimeInterval(-1)))
        let store = store(now: now)
        await store.restore()
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: .expired))
        #expect(server.requests.isEmpty)
        #expect(vault.stored == nil)
    }

    @Test("Launch shows the archive at once and checks the session behind it")
    func restoreValid() async throws {
        let server = MockServer { _ in .json(#"{"authenticated": true, "auth_required": true, "role": "viewer"}"#) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try vault.save(stored(server, expires: now.addingTimeInterval(3600)))
        let store = store(now: now)
        await store.restore()
        #expect(try readySession(store).stored.cookie == "old-session")
        #expect(server.requests.map(\.path) == ["/api/auth/check"])
        #expect(server.requests.first?.cookie == "viewer_auth=old-session")
        #expect(store.connectionProblem == nil)
    }

    @Test("Launch: a session the server no longer knows ends")
    func restoreEnded() async throws {
        let server = MockServer { _ in .json(#"{"authenticated": false, "auth_required": true}"#) }
        try vault.save(stored(server))
        let store = store()
        await store.restore()
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: .ended))
        #expect(vault.stored == nil)
    }

    @Test("Launch offline keeps the session and reports the problem")
    func restoreOffline() async throws {
        let server = MockServer { _ in .transportFailure(.notConnectedToInternet) }
        try vault.save(stored(server))
        let store = store()
        await store.restore()
        _ = try readySession(store)
        #expect(store.connectionProblem == .transport(.notConnectedToInternet))
        #expect(vault.stored != nil)
    }

    @Test("First launch of a new install releases the session a previous install left in the Keychain")
    func reinstallCleanup() async throws {
        let server = MockServer(handler: Self.archive())
        try vault.save(stored(server))
        defaults.removeObject(forKey: "installMarker")
        let store = store()
        await store.restore()
        #expect(store.phase == .connect)
        #expect(vault.stored == nil)
        #expect(server.requests.map(\.path) == ["/api/logout"])
        #expect(server.requests.first?.cookie == "viewer_auth=old-session")
        #expect(defaults.bool(forKey: "installMarker"))

        // The marker is written once: the next launch keeps what is stored.
        try vault.save(stored(server))
        await SessionStore(vault: vault, defaults: defaults, configuration: MockServer.configuration(), cache: cache)
            .restore()
        #expect(vault.stored != nil)
    }

    // MARK: Sign out and session end

    private func cachedSample(_ server: MockServer) -> URLRequest {
        let request = URLRequest(url: server.address.baseURL.appending(path: "media/thumb/400/R/1_photo"))
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        cache.storeCachedResponse(CachedURLResponse(response: response, data: Data([1, 2, 3])), for: request)
        return request
    }

    @Test("Sign-out tells the server with the cookie, then wipes everything local")
    func signOut() async throws {
        let server = MockServer(handler: Self.archive())
        try vault.save(stored(server))
        let store = store()
        let wipes = Counter()
        store.addWipeStep { wipes.count += 1 }
        await store.restore()
        let sample = cachedSample(server)
        #expect(cache.cachedResponse(for: sample) != nil)

        await store.signOut()
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: nil))
        #expect(server.requests.last?.path == "/api/logout")
        #expect(server.requests.last?.cookie == "viewer_auth=old-session")
        #expect(vault.stored == nil)
        #expect(cache.cachedResponse(for: sample) == nil)
        #expect(wipes.count == 1)
        #expect(!store.lastSignOutWasLocalOnly)
    }

    @Test("Sign-out wipes even when the server cannot be reached")
    func signOutOffline() async throws {
        let server = MockServer { request in
            request.path == "/api/logout"
                ? .transportFailure(.notConnectedToInternet)
                : .json(#"{"authenticated": true, "auth_required": true}"#)
        }
        try vault.save(stored(server))
        let store = store()
        let wipes = Counter()
        store.addWipeStep { wipes.count += 1 }
        await store.restore()
        let sample = cachedSample(server)

        await store.signOut()
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: nil))
        #expect(vault.stored == nil)
        #expect(cache.cachedResponse(for: sample) == nil)
        #expect(wipes.count == 1)
        #expect(store.lastSignOutWasLocalOnly)
    }

    @Test("Disconnecting from an anonymous server makes no server call")
    func disconnectAnonymous() async throws {
        let server = MockServer { _ in .json(#"{"authenticated": false, "auth_required": false}"#) }
        let store = store()
        try await store.connect(server.address.baseURL.absoluteString)
        await store.signOut()
        #expect(store.phase == .connect)
        #expect(server.requests.map(\.path) == ["/api/auth/check"])
        #expect(vault.stored == nil)
    }

    @Test("A burst of 401s makes one transition and one wipe")
    func unauthorizedBurst() async throws {
        let server = MockServer { _ in .json(#"{"authenticated": true, "auth_required": true}"#) }
        try vault.save(stored(server))
        let store = store()
        let wipes = Counter()
        store.addWipeStep {
            wipes.count += 1
            try? await Task.sleep(for: .milliseconds(50))
        }
        await store.restore()
        let client = try readySession(store).client

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { await store.sessionEnded(client) }
            }
        }
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: .ended))
        #expect(wipes.count == 1)
        #expect(vault.stored == nil)
        #expect(server.requests(to: "/api/logout").isEmpty)
    }

    @Test("A late 401 from an older session's client does not end the new one")
    func stale401Ignored() async throws {
        let server = MockServer(handler: Self.archive())
        try vault.save(stored(server))
        let store = store()
        await store.restore()
        let oldClient = try readySession(store).client
        try await store.signIn(username: "admin", password: "pw")

        await store.sessionEnded(oldClient)
        #expect(try readySession(store).stored.cookie == "new-session")
        #expect(vault.stored != nil)
    }
}
