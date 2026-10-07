import Foundation
import Synchronization
import Testing
import UIKit
@testable import TGArchive

/// A PNG of the given size in pixels.
func pngData(width: Int, height: Int) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
    return renderer.pngData { context in
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
}

/// Counts the clients the loader reports as ended.
final class EndedClients: Sendable {
    private let clients = Mutex<[ObjectIdentifier]>([])
    var count: Int { clients.withLock { $0.count } }
    func record(_ client: APIClient) { clients.withLock { $0.append(ObjectIdentifier(client)) } }
    func contains(_ client: APIClient) -> Bool { clients.withLock { $0.contains(ObjectIdentifier(client)) } }
}

@Suite("Media loader")
struct MediaLoaderTests {
    private let server = MockServer()
    private let ended = EndedClients()

    private func loader(cookie: String? = "media-session") -> MediaLoader {
        let client = APIClient(server: server.address, cookie: cookie, configuration: MockServer.configuration(),
                               cache: MockServer.cache())
        let ended = ended
        return MediaLoader(client: client, files: FileStore(root: Self.scratch())) { ended.record($0) }
    }

    private static func scratch() -> URL {
        URL.temporaryDirectory.appending(path: "tgarchive-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private static let png = pngData(width: 800, height: 400)

    @Test("An avatar loads with the session cookie and decodes to the asked size")
    func loads() async throws {
        server.respond { _ in .init(status: 200, headers: ["Content-Type": "image/png", "ETag": "\"a1\""], body: Self.png) }
        let loader = loader()
        let image = try await loader.image(for: .avatar(ref: "chat-ref"), maxPixelSize: 200)
        #expect(max(image.size.width, image.size.height) * image.scale <= 200)
        #expect(image.size.width * image.scale == 200)
        let request = try #require(server.requests.first)
        #expect(request.path == "/media/avatar/chat-ref")
        #expect(request.cookie == "viewer_auth=media-session")
    }

    @Test("Every load asks the server again, so its access checks run each time")
    func revalidatesEveryLoad() async throws {
        server.respond { _ in .init(status: 200, headers: ["ETag": "\"same\""], body: Self.png) }
        let loader = loader()
        let first = try await loader.image(for: .thumbnail(size: .large, ref: "r", key: "1_photo"), maxPixelSize: 400)
        let second = try await loader.image(for: .thumbnail(size: .large, ref: "r", key: "1_photo"), maxPixelSize: 400)
        #expect(server.requests.count == 2)
        // Same ETag: the decoded image is reused, only the decode is spared.
        #expect(first === second)
    }

    @Test("Loads of one image in flight together share one request")
    func sharesInFlight() async throws {
        server.respond { _ in
            Thread.sleep(forTimeInterval: 0.3)
            return .init(status: 200, body: Self.png)
        }
        let loader = loader()
        async let a = loader.image(for: .avatar(ref: "shared"), maxPixelSize: 100)
        async let b = loader.image(for: .avatar(ref: "shared"), maxPixelSize: 100)
        async let c = loader.image(for: .avatar(ref: "shared"), maxPixelSize: 100)
        let images = try await [a, b, c]
        #expect(images.count == 3)
        #expect(server.requests.count == 1)
    }

    @Test("403 is the downloads-off tile, 404 the missing tile, and neither ends the session")
    func forbiddenAndMissing() async {
        let loader = loader()
        server.respond { _ in .json(#"{"detail": "Downloads disabled for this account"}"#, status: 403) }
        await #expect(throws: MediaFailure.downloadsOff) {
            try await loader.image(for: .thumbnail(size: .large, ref: "r", key: "2_photo"), maxPixelSize: 400)
        }
        server.respond { _ in .json(#"{"detail": "Not found"}"#, status: 404) }
        await #expect(throws: MediaFailure.missing) {
            try await loader.image(for: .thumbnail(size: .large, ref: "r", key: "3_video"), maxPixelSize: 400)
        }
        #expect(ended.count == 0)
    }

    @Test("A 401 tells the session store, with the client that got it")
    func unauthorized() async {
        server.respond { _ in .json(#"{"detail": "Not authenticated"}"#, status: 401) }
        let loader = loader()
        await #expect(throws: MediaFailure.sessionEnded) {
            try await loader.image(for: .avatar(ref: "gone"), maxPixelSize: 100)
        }
        #expect(ended.count == 1)
        #expect(ended.contains(loader.client))
    }

    @Test("Bytes that are not an image fail as undecodable")
    func undecodable() async {
        server.respond { _ in .init(status: 200, body: Data("not an image".utf8)) }
        await #expect(throws: MediaFailure.undecodable) {
            try await loader().image(for: .avatar(ref: "bad"), maxPixelSize: 100)
        }
    }

    @Test("A load nobody waits for any more is cancelled")
    func cancellation() async {
        server.respond { _ in
            Thread.sleep(forTimeInterval: 0.5)
            return .init(status: 200, body: Self.png)
        }
        let loader = loader()
        let task = Task { try await loader.image(for: .avatar(ref: "slow"), maxPixelSize: 100) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.result
        #expect(throws: MediaFailure.failed(.transport(.cancelled))) { try result.get() }
        // A new load after the cancelled one starts its own request.
        server.respond { _ in .init(status: 200, body: Self.png) }
        _ = try? await loader.image(for: .avatar(ref: "slow"), maxPixelSize: 100)
        #expect(server.requests.count == 2)
    }

    @Test("A document lands under its ref and key with a safe name; 403 and wipe behave")
    func files() async throws {
        let root = Self.scratch()
        let store = FileStore(root: root)
        let client = APIClient(server: server.address, cookie: "files", configuration: MockServer.configuration(),
                               cache: MockServer.cache())
        server.respond { _ in .init(status: 200, headers: ["Content-Type": "application/pdf"], body: Data("%PDF".utf8)) }
        let url = try await store.download(ref: "ref", key: "12_document", fileName: "../../notes.pdf", client: client)
        #expect(url == root.appending(path: "ref/12_document/notes.pdf"))
        #expect(try Data(contentsOf: url) == Data("%PDF".utf8))
        #expect(server.requests.first?.path == "/media/ref/12_document")
        // Downloading again replaces the file.
        _ = try await store.download(ref: "ref", key: "12_document", fileName: "../../notes.pdf", client: client)

        server.respond { _ in .json(#"{"detail": "Downloads disabled for this account"}"#, status: 403) }
        await #expect(throws: MediaFailure.downloadsOff) {
            try await store.download(ref: "ref", key: "13_document", fileName: nil, client: client)
        }
        store.wipe()
        #expect(!FileManager.default.fileExists(atPath: root.path(percentEncoded: false)))
    }

    @Test("File names from the server cannot leave the folder")
    func safeNames() {
        #expect(FileStore.safeName("../../etc/passwd") == "passwd")
        #expect(FileStore.safeName("..") == nil)
        #expect(FileStore.safeName(".hidden") == "hidden")
        #expect(FileStore.safeName("a:b.txt") == "a_b.txt")
        #expect(FileStore.safeName("") == nil)
        let root = URL(filePath: "/tmp/Media/")
        let url = FileStore(root: root).destination(ref: "../x", key: "1_document", fileName: nil)
        #expect(url.path(percentEncoded: false) == "/tmp/Media/x/1_document/1_document")
    }
}

@MainActor
@Suite("Media wipe")
struct MediaWipeTests {
    @Test("One loader per session; sign-out drops it and deletes the downloaded files")
    func wipe() async throws {
        let server = MockServer { request in
            switch request.path {
            case "/api/auth/check": .json(#"{"authenticated": true, "auth_required": true, "role": "viewer"}"#)
            default: .json(#"{"success": true}"#)
            }
        }
        let vault = MemoryVault(StoredSession(server: server.address, cookie: "c", cookieExpires: nil,
                                              username: "family", role: .viewer, noDownload: false))
        let suite = "tgarchive.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "installMarker")
        let store = SessionStore(vault: vault, defaults: defaults, configuration: MockServer.configuration(),
                                 cache: MockServer.cache())
        await store.restore()
        guard case let .ready(session) = store.phase else {
            Issue.record("expected a ready session, got \(store.phase)")
            return
        }
        let loader = MediaLoader.current(for: session, in: store)
        #expect(MediaLoader.current(for: session, in: store) === loader)

        let marker = FileStore.shared.root.appending(path: "ref/1_document/file.txt")
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: marker)

        await store.signOut()
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
        await store.restore()
        #expect(store.phase == .connect)
    }
}

/// Against the demo server: the HTTP cache revalidates media with the server, and after sign-out nothing
/// cached is shown.
@Suite("Live media", .serialized, .enabled(if: LiveServer.baseURL != nil, "TGARCHIVE_DEMO_URL is not set"))
struct LiveMediaTests {
    /// The status of every network transaction of one request, as the system saw it.
    final class Metrics: NSObject, URLSessionTaskDelegate, Sendable {
        private let statuses = Mutex<[Int]>([])
        var networkStatuses: [Int] { statuses.withLock { $0 } }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            let codes = metrics.transactionMetrics
                .filter { $0.resourceFetchType == .networkLoad }
                .compactMap { ($0.response as? HTTPURLResponse)?.statusCode }
            statuses.withLock { $0 += codes }
        }
    }

    @MainActor
    @Test("An avatar is revalidated with a 304, and after sign-out the old cookie gets 401, not the cached copy")
    func revalidationAndSignOut() async throws {
        let baseURL = try #require(LiveServer.baseURL)
        let vault = MemoryVault()
        let suite = "tgarchive.live.media.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "installMarker")
        let cache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0, directory: nil)
        let store = SessionStore(vault: vault, defaults: defaults, configuration: .ephemeral, cache: cache)

        // One sign-in for the whole test: sign-ins share a limit of 15 per client IP in 5 minutes.
        try await store.connect(baseURL)
        try await store.signIn(username: LiveServer.username, password: LiveServer.password)
        guard case let .ready(session) = store.phase else {
            Issue.record("not signed in: \(store.phase)")
            return
        }
        let client = session.client
        let chats: ChatsPage = try await client.get(.chats())
        let chat = try #require(chats.chats.first { $0.avatarURL != nil })
        let request = client.request(for: .avatar(ref: chat.ref))

        let first = Metrics()
        let (firstData, firstResponse) = try await client.urlSession.data(for: request, delegate: first)
        #expect((firstResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(first.networkStatuses == [200])
        #expect(cache.cachedResponse(for: request) != nil)

        let second = Metrics()
        let (secondData, secondResponse) = try await client.urlSession.data(for: request, delegate: second)
        #expect((secondResponse as? HTTPURLResponse)?.statusCode == 200)
        #expect(secondData == firstData)
        // The cached copy was not reused on its own: the server was asked and answered 304.
        #expect(second.networkStatuses == [304])

        let loader = MediaLoader.current(for: session, in: store)
        let image = try await loader.image(for: .avatar(ref: chat.ref), maxPixelSize: 160)
        #expect(image.size.width > 0)

        await store.signOut()
        #expect(cache.cachedResponse(for: request) == nil)

        // A client still holding the old cookie and the same cache gets 401, never the copy it kept.
        let stale = APIClient(server: session.stored.server, cookie: session.stored.cookie,
                              configuration: .ephemeral, cache: cache)
        let staleEnded = EndedClients()
        let staleLoader = MediaLoader(client: stale, files: FileStore(root: URL.temporaryDirectory
            .appending(path: "tgarchive-live-\(UUID().uuidString)"))) { staleEnded.record($0) }
        await #expect(throws: MediaFailure.sessionEnded) {
            try await staleLoader.image(for: .avatar(ref: chat.ref), maxPixelSize: 160)
        }
        #expect(staleEnded.count == 1)
    }
}
