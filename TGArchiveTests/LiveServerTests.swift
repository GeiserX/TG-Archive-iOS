import Foundation
import Testing
@testable import TGArchive

/// Runs against a real Telegram-Archive server when `TGARCHIVE_DEMO_URL` is set (scripts/mini-test.sh hands
/// it over; scripts/demo-server.sh starts one). It signs in once per run and signs out at the end, because
/// login and share-link login share a limit of 15 attempts per client IP in 5 minutes.
enum LiveServer {
    static var baseURL: String? {
        let value = ProcessInfo.processInfo.environment["TGARCHIVE_DEMO_URL"] ?? ""
        return value.isEmpty ? nil : value
    }

    /// The demo server's master login: public constants of scripts/demo-server.sh, overridable.
    static var username: String { ProcessInfo.processInfo.environment["TGARCHIVE_DEMO_USERNAME"] ?? "admin" }
    static var password: String {
        ProcessInfo.processInfo.environment["TGARCHIVE_DEMO_PASSWORD"] ?? "demo-admin-not-a-secret"
    }
}

@MainActor
@Suite("Live demo server", .serialized, .enabled(if: LiveServer.baseURL != nil, "TGARCHIVE_DEMO_URL is not set"))
struct LiveServerTests {
    @Test("Sign in once as the master, list chats, read a page and the one before it, sign out")
    func signInReadSignOut() async throws {
        let baseURL = try #require(LiveServer.baseURL)
        // An in-memory vault, so the app's real Keychain item is never touched.
        let vault = MemoryVault()
        let suite = "tgarchive.live.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "installMarker")
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, directory: nil)
        let store = SessionStore(vault: vault, defaults: defaults, configuration: .ephemeral, cache: cache)

        try await store.connect(baseURL)
        guard case .signIn = store.phase else {
            Issue.record("the demo server should need a login, got \(store.phase)")
            return
        }
        try await store.signIn(username: LiveServer.username, password: LiveServer.password)
        guard case let .ready(session) = store.phase else {
            Issue.record("not signed in: \(store.phase)")
            return
        }
        #expect(session.stored.role == .master)
        #expect(session.stored.cookie?.isEmpty == false)
        #expect(session.stored.cookieExpires.map { $0 > Date() } == true)
        #expect(vault.stored == session.stored)

        let client = session.client
        let chats: ChatsPage = try await client.get(.chats())
        #expect(!chats.chats.isEmpty)
        #expect(chats.chats.allSatisfy { !$0.isArchived })
        let archivedCount: ArchivedCount = try await client.get(.archivedCount)
        let everything: ChatsPage = try await client.get(.chats(archived: nil))
        #expect(everything.chats.count == chats.chats.count + archivedCount.count)

        let chat = try #require(chats.chats.first { !$0.isForum && $0.preview != nil })
        let page: MessagePage = try await client.get(.messages(ref: chat.ref, limit: 5))
        #expect(page.dropped == 0)
        #expect(page.messages.count == 5)
        #expect(page.messages.first?.id == chat.preview?.messageID)

        // The cursor goes back in the format the server parses: the page before is strictly older.
        let oldest = try #require(page.messages.last)
        let older: MessagePage = try await client.get(
            .messages(ref: chat.ref, limit: 5, cursor: .before(date: oldest.date, id: oldest.id)))
        #expect(older.dropped == 0)
        #expect(older.messages.allSatisfy { ($0.date, $0.id) < (oldest.date, oldest.id) })
        #expect(Set(older.messages.map(\.id)).isDisjoint(with: page.messages.map(\.id)))

        await store.signOut()
        #expect(store.phase == .signIn(session.stored.server, prefilledToken: nil, reason: nil))
        #expect(!store.lastSignOutWasLocalOnly)
        #expect(vault.stored == nil)

        // The server ended the session too: the old cookie no longer opens anything.
        let stale = APIClient(server: session.stored.server, cookie: session.stored.cookie,
                              configuration: .ephemeral, cache: cache)
        await #expect(throws: APIError.unauthorized) { let _: ChatsPage = try await stale.get(.chats()) }
    }

    /// What `NSAllowsLocalNetworking` lets through over plain http on this OS. An address ATS blocks fails at
    /// once with `appTransportSecurityRequiresSecureConnection`; any other outcome (an answer, refused, no
    /// such host, timed out) means ATS let the request go.
    @Test("ATS lets plain http reach loopback, local names and private IPv4, and blocks public hosts")
    func appTransportSecurity() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        func blockedByATS(_ address: String) async -> Bool {
            do {
                _ = try await session.data(from: URL(string: address)!)
                return false
            } catch let error as URLError {
                print("ATS probe \(address): URLError \(error.code.rawValue)")
                return error.code == .appTransportSecurityRequiresSecureConnection
            } catch {
                return false
            }
        }

        let baseURL = try #require(LiveServer.baseURL)
        #expect(await !blockedByATS("\(baseURL)/api/health"))
        #expect(await !blockedByATS("http://127.0.0.1:9/"))
        #expect(await !blockedByATS("http://localhost:9/"))
        #expect(await !blockedByATS("http://tgarchive-probe.local:9/"))
        #expect(await !blockedByATS("http://tgarchive-probe:9/"))
        #expect(await !blockedByATS("http://10.255.255.1:9/"))
        #expect(await !blockedByATS("http://192.168.255.254:9/"))
        #expect(await blockedByATS("http://example.com/"))
        #expect(await blockedByATS("http://1.1.1.1/"))
    }
}
