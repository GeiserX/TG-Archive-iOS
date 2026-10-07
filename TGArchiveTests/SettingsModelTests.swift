import Foundation
import Testing
@testable import TGArchive

@MainActor
@Suite("Settings")
struct SettingsModelTests {
    private let vault = MemoryVault()
    private let cache = MockServer.cache()

    /// A store signed in to `server` through the sign-in flow.
    private func signedIn(_ server: MockServer, token: Bool = false) async throws -> (SessionStore, Session) {
        let store = FakeArchive.store(vault: vault, cache: cache)
        try await store.connect(server.address.baseURL.absoluteString)
        if token {
            try await store.signIn(token: "demo-share-link-not-a-secret")
        } else {
            try await store.signIn(username: "admin", password: "pw")
        }
        guard case let .ready(session) = store.phase else { throw CancellationError() }
        return (store, session)
    }

    private func stored(role: StoredSession.Role, username: String?) -> StoredSession {
        StoredSession(server: ServerAddress.parse("archive.example.com")!.address, cookie: "c", cookieExpires: nil,
                      username: username, role: role, noDownload: false)
    }

    @Test("Who is signed in: owner and viewer show their name, a share link its label, an open server neither")
    func signedInAs() {
        let owner = stored(role: .master, username: "admin")
        #expect(SettingsModel.accountName(for: owner) == "admin")
        #expect(SettingsModel.roleLabel(for: owner) == String(localized: "settings.role.master"))

        let viewer = stored(role: .viewer, username: "family")
        #expect(SettingsModel.accountName(for: viewer) == "family")
        #expect(SettingsModel.roleLabel(for: viewer) == String(localized: "settings.role.viewer"))

        let link = stored(role: .token, username: "token:Hike photos")
        #expect(SettingsModel.accountName(for: link) == nil)
        #expect(SettingsModel.roleLabel(for: link).contains("Hike photos"))
        #expect(!SettingsModel.roleLabel(for: link).contains("token:"))

        let unnamed = stored(role: .token, username: "token:")
        #expect(SettingsModel.roleLabel(for: unnamed) == String(localized: "settings.role.token"))

        let open = stored(role: .anonymous, username: nil)
        #expect(SettingsModel.accountName(for: open) == nil)
        #expect(SettingsModel.roleLabel(for: open) == String(localized: "settings.role.anonymous"))

        let labels = [owner, viewer, unnamed, open].map(SettingsModel.roleLabel(for:))
        #expect(Set(labels).count == labels.count)
    }

    @Test("The archive figures load from /api/stats and show when the server allows it")
    func statsShown() async throws {
        let server = MockServer(handler: FakeArchive.handler())
        let (store, session) = try await signedIn(server)
        let model = SettingsModel()

        await model.load(session, store: store)

        let stats = try #require(model.visibleStats)
        #expect(stats.chats == 16)
        #expect(stats.messages == 409)
        #expect(stats.mediaFiles == 46)
        #expect(stats.lastBackupTime != nil)
        #expect(server.requests(to: "/api/stats").first?.cookie == "viewer_auth=\(FakeArchive.cookie)")
    }

    @Test("The archive figures stay hidden when the server's owner turned them off")
    func statsHidden() async throws {
        let server = MockServer(handler: FakeArchive.handler(
            stats: .json(#"{"chats": 3, "messages": 40, "show_stats": false}"#)))
        let (store, session) = try await signedIn(server)
        let model = SettingsModel()

        await model.load(session, store: store)

        #expect(model.stats?.chats == 3)
        #expect(model.visibleStats == nil)
    }

    @Test("A 401 on the figures ends the session; an offline server is a banner and keeps it")
    func statsErrors() async throws {
        let server = MockServer(handler: FakeArchive.handler())
        let (store, session) = try await signedIn(server)
        let model = SettingsModel()

        server.respond { _ in .transportFailure(.notConnectedToInternet) }
        await model.load(session, store: store)
        #expect(model.error == .transport(.notConnectedToInternet))
        #expect(store.phase == .ready(session))

        server.respond { _ in .json(#"{"detail": "Not authenticated"}"#, status: 401) }
        await model.load(session, store: store)
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: .ended))
        #expect(vault.stored == nil)
    }

    @Test("Sign out tells the server with the cookie, then wipes the session and returns to sign-in")
    func signOut() async throws {
        let server = MockServer(handler: FakeArchive.handler(signedIn: "auth-check-token"))
        let (store, _) = try await signedIn(server, token: true)
        #expect(vault.stored != nil)
        let model = SettingsModel()

        await model.signOut(using: store)

        let logout = try #require(server.requests(to: "/api/logout").last)
        #expect(logout.cookie == "viewer_auth=\(FakeArchive.cookie)")
        #expect(vault.stored == nil)
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: nil))
        #expect(!store.lastSignOutWasLocalOnly)
        #expect(!model.isSigningOut)
    }

    @Test("Disconnect from an open server calls nothing and returns to connect")
    func disconnect() async throws {
        let server = MockServer { _ in .json(#"{"authenticated": false, "auth_required": false}"#) }
        let store = FakeArchive.store(vault: vault, cache: cache)
        try await store.connect(server.address.baseURL.absoluteString)
        let before = server.requests.count
        let model = SettingsModel()

        await model.signOut(using: store)

        #expect(server.requests.count == before)
        #expect(store.phase == .connect)
        #expect(vault.stored == nil)
    }

    @Test("Clear cache empties the HTTP cache and the downloaded files, and keeps the session")
    func clearCache() async throws {
        let server = MockServer(handler: FakeArchive.handler())
        let (store, session) = try await signedIn(server)
        let url = Endpoint.thumbnail(size: .large, ref: "c1", key: "1_photo").url(base: server.address.baseURL)
        let request = URLRequest(url: url)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        cache.storeCachedResponse(CachedURLResponse(response: response, data: Data([1, 2, 3])), for: request)
        #expect(cache.cachedResponse(for: request) != nil)
        let model = SettingsModel()

        let file = FileStore.shared.root.appending(path: "c1/1_document/notes.txt")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: file)

        await model.clearCache(session, store: store)

        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))

        #expect(cache.cachedResponse(for: request) == nil)
        #expect(model.cacheCleared)
        #expect(store.phase == .ready(session))
        #expect(vault.stored != nil)
    }
}
