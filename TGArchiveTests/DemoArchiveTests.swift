import Foundation
import Testing
import UIKit
@testable import TGArchive

/// "Try the demo": the bundled archive answers the routes the app calls, through an ordinary `APIClient`, and
/// the demo session never touches the Keychain or a server.
@MainActor
@Suite("Demo archive")
struct DemoArchiveTests {
    private let client = DemoArchive.client()
    private static let hikers = "C9uWzfb7MCkzaP28_9kOKA"
    private static let forum = "UtB4DrfIxOJyfIL1mRcO0w"

    @Test("The chat list, the archived list, the folders and the figures decode")
    func lists() async throws {
        let page: ChatsPage = try await client.get(.chats())
        #expect(page.chats.count == 14)
        #expect(page.chats.first?.ref == Self.hikers)
        #expect(!page.hasMore)
        let archived: ChatsPage = try await client.get(.chats(archived: true))
        #expect(archived.chats.count == 1)
        let count: ArchivedCount = try await client.get(.archivedCount)
        #expect(count.count == 1)
        let folders: FolderList = try await client.get(.folders)
        #expect(folders.folders.map(\.id) == [2, 3])
        let friends: ChatsPage = try await client.get(.chats(folderID: 2))
        #expect(friends.chats.count == 6)
        #expect(friends.chats.allSatisfy { $0.type == "private" })
        let found: ChatsPage = try await client.get(.chats(search: "book"))
        #expect(found.chats.map(\.ref) == ["62CLdN3oC13zajv4KawzYw"])
        let stats: ArchiveStats = try await client.get(.stats)
        #expect(stats.messages == 409)
    }

    @Test("A thread pages back by date to its oldest message, and every message decodes")
    func paging() async throws {
        var page: MessagePage = try await client.get(.messages(ref: Self.hikers, limit: 30))
        #expect(page.messages.count == 30)
        #expect(page.dropped == 0)
        var seen = page.messages.map(\.id)
        while let last = page.messages.last {
            page = try await client.get(.messages(ref: Self.hikers, limit: 30, cursor: .before(date: last.date, id: last.id)))
            #expect(page.dropped == 0)
            seen += page.messages.map(\.id)
        }
        #expect(seen.count == 76)
        #expect(Set(seen).count == seen.count, "a page repeated a message")
    }

    @Test("The id cursors around a search hit, and a forum topic")
    func cursors() async throws {
        let before: MessagePage = try await client.get(.messages(ref: Self.hikers, limit: 5, cursor: .beforeID(1250)))
        #expect(before.messages.map(\.id) == [1249, 1248, 1247, 1246, 1245])
        let after: MessagePage = try await client.get(.messages(ref: Self.hikers, limit: 3, cursor: .after(id: 1250)))
        #expect(after.messages.map(\.id) == [1253, 1252, 1251])
        let topics: TopicList = try await client.get(.topics(ref: Self.forum))
        let events = try #require(topics.topics.first { $0.title == "Events" })
        let topic: MessagePage = try await client.get(.messages(ref: Self.forum, topicID: events.id))
        #expect(topic.messages.count == 9)
    }

    @Test("Search finds text in every chat, newest first, and opens nothing it did not find")
    func search() async throws {
        let page: SearchPage = try await client.get(.search(query: "trail"))
        #expect(!page.results.isEmpty)
        #expect(page.results.allSatisfy { $0.text?.localizedStandardContains("trail") == true })
        #expect(page.results.map(\.date) == page.results.map(\.date).sorted(by: >))
        #expect(page.indexed)
        let none: SearchPage = try await client.get(.search(query: "no such words anywhere"))
        #expect(none.results.isEmpty)
    }

    @Test("Bundled photos load as images; other media and unknown routes are 404")
    func media() async throws {
        let request = client.request(for: .thumbnail(size: .large, ref: Self.hikers, key: "1274_photo"))
        let (data, response) = try await client.urlSession.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(UIImage(data: data) != nil)
        do {
            let _: Chat = try await client.get(.chat(ref: "not-a-chat"))
            Issue.record("an unknown chat answered")
        } catch {
            #expect(error == .notFound)
        }
        let avatar = try await client.urlSession.data(for: client.request(for: .avatar(ref: Self.hikers)))
        #expect((avatar.1 as? HTTPURLResponse)?.statusCode == 404)
    }

    @Test("Every bundled message decodes, and every photo it shows is bundled")
    func bundleIsComplete() async throws {
        let chats: ChatsPage = try await client.get(.chats())
        let archived: ChatsPage = try await client.get(.chats(archived: true))
        var photos = 0
        for chat in chats.chats + archived.chats {
            let page: MessagePage = try await client.get(.messages(ref: chat.ref, limit: 500))
            #expect(page.dropped == 0, "\(chat.ref) dropped messages")
            for message in page.messages {
                guard let media = message.media, media.type == .photo, media.downloaded else { continue }
                photos += 1
                #expect(Bundle.main.url(forResource: "demo-\(chat.ref)-\(media.id)", withExtension: "jpg") != nil,
                        "no bundled photo for \(chat.ref)/\(media.id)")
            }
        }
        #expect(photos == 27)
    }

    @Test("The demo opens without the Keychain or a server, and Exit Demo returns to connect")
    func session() async throws {
        let vault = MemoryVault()
        let store = FakeArchive.store(vault: vault)
        await store.restore()
        #expect(store.phase == .connect)
        await store.startDemo()
        guard case let .ready(session) = store.phase else {
            Issue.record("the demo did not open: \(store.phase)")
            return
        }
        #expect(session.isDemo)
        #expect(vault.stored == nil, "the demo was saved to the Keychain")
        #expect(store.lastServer == nil, "the demo became the last server")
        let stats: ArchiveStats = try await session.client.get(.stats)
        #expect(stats.chats == 16)
        await store.signOut()
        #expect(store.phase == .connect)
        #expect(!store.lastSignOutWasLocalOnly)
    }

    @Test("A real server is never a demo")
    func realServerIsNotDemo() throws {
        let server = try #require(ServerAddress.parse("https://archive.example.com")).address
        let stored = StoredSession(server: server, cookie: nil, cookieExpires: nil, username: nil, role: .anonymous,
                                   noDownload: false)
        #expect(!Session(stored: stored, client: client).isDemo)
        #expect(!DemoURLProtocol.canInit(with: URLRequest(url: server.baseURL)))
    }
}
