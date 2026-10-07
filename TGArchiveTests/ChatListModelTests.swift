import Foundation
import Synchronization
import Testing
@testable import TGArchive

/// Records the clients a model hands to `sessionEnded`.
@MainActor
final class SessionEndRecorder {
    var clients: [APIClient] = []
    func record(_ client: APIClient) { clients.append(client) }
}

@MainActor
@Suite("Chat list model")
struct ChatListModelTests {
    private let server = MockServer()
    private let recorder = SessionEndRecorder()

    private func model(archived: Bool = false) -> ChatListModel {
        let client = APIClient(server: server.address, cookie: "list-session",
                               configuration: MockServer.configuration(), cache: MockServer.cache())
        return ChatListModel(client: client, archived: archived) { [recorder] in recorder.record($0) }
    }

    /// A `/api/chats` page with one private chat per ref.
    private nonisolated static func page(_ refs: [String], hasMore: Bool) -> MockServer.Response {
        let rows = refs.map { ref in
            #"{"ref": "\#(ref)", "type": "private", "title": null, "first_name": "Name \#(ref)", "is_forum": 0, "#
                + #""is_archived": 0, "accounts": [1], "avatar_url": null, "preview": null}"#
        }
        return .json(#"{"chats": [\#(rows.joined(separator: ","))], "total": 99, "limit": 50, "offset": 0, "#
            + #""has_more": \#(hasMore)}"#)
    }

    /// The demo archive's answers for the chat list routes.
    private nonisolated static func archive(_ request: MockServer.Recorded) -> MockServer.Response {
        switch request.path {
        case "/api/chats": (try? .fixture("chats")) ?? .init(status: 500)
        case "/api/archived/count": (try? .fixture("archived-count")) ?? .init(status: 500)
        case "/api/folders": (try? .fixture("folders")) ?? .init(status: 500)
        default: .json(#"{"detail": "Not Found"}"#, status: 404)
        }
    }

    @Test("The first page asks for 50 unarchived chats and brings the archived count and the folders")
    func firstPage() async throws {
        server.respond(Self.archive)
        let model = model()
        await model.open(.init())

        let request = try #require(server.requests(to: "/api/chats").first)
        #expect(request.query == ["limit": "50", "offset": "0", "archived": "false"])
        #expect(request.cookie == "viewer_auth=list-session")
        #expect(server.requests(to: "/api/archived/count").count == 1)
        #expect(server.requests(to: "/api/folders").count == 1)
        #expect(model.chats.count == 14)
        #expect(model.chats.first?.displayTitle == "Weekend Hikers")
        #expect(!model.hasMore)
        #expect(model.archivedCount == 1)
        #expect(model.folders.map(\.title) == ["Friends", "Hobbies"])
        #expect(model.error == nil)
        #expect(!model.isLoading)
        #expect(model.appliedQuery == .init())
    }

    @Test("Opening the same query again keeps the pages instead of reloading")
    func openIsIdempotent() async {
        server.respond(Self.archive)
        let model = model()
        await model.open(.init())
        await model.open(.init(search: "   "))
        #expect(server.requests(to: "/api/chats").count == 1)
    }

    @Test("has_more pages by offset, drops a ref repeated across pages, and stops at the last page")
    func paging() async {
        server.respond { request in
            switch request.query["offset"] {
            case "0": Self.page(["a", "b"], hasMore: true)
            case "2": Self.page(["b", "c"], hasMore: false)
            default: .init(status: 500)
            }
        }
        let model = model()
        await model.open(.init())
        #expect(model.hasMore)
        await model.loadMore()
        #expect(server.requests(to: "/api/chats").map { $0.query["offset"] } == ["0", "2"])
        #expect(model.chats.map(\.ref) == ["a", "b", "c"])
        #expect(!model.hasMore)
        await model.loadMore()
        #expect(server.requests(to: "/api/chats").count == 2)
    }

    @Test("A search goes to the server, from offset 0, without the side requests")
    func search() async throws {
        server.respond { request in
            request.query["search"] == "hik" ? Self.page(["h"], hasMore: false) : Self.page(["a", "b"], hasMore: true)
        }
        let model = model()
        await model.open(.init())
        await model.loadMore()
        await model.open(.init(search: " hik "))
        let last = try #require(server.requests(to: "/api/chats").last)
        #expect(last.query["search"] == "hik")
        #expect(last.query["offset"] == "0")
        #expect(model.chats.map(\.ref) == ["h"])
        #expect(server.requests(to: "/api/archived/count").count == 1)
    }

    @Test("A folder filters on the server")
    func folder() async throws {
        server.respond { _ in Self.page(["f"], hasMore: false) }
        let model = model()
        await model.open(.init(folderID: 3))
        let request = try #require(server.requests(to: "/api/chats").first)
        #expect(request.query["folder_id"] == "3")
        #expect(server.requests(to: "/api/folders").isEmpty)
    }

    @Test("The archived list asks for archived=true and nothing else")
    func archived() async throws {
        server.respond { _ in Self.page(["z"], hasMore: false) }
        let model = model(archived: true)
        await model.open(.init(folderID: 2))
        let request = try #require(server.requests(to: "/api/chats").first)
        #expect(request.query == ["limit": "50", "offset": "0", "archived": "true"])
        #expect(server.requests.count == 1)
        #expect(model.archivedCount == 0)
    }

    @Test("Pull to refresh loads the first page again")
    func refresh() async {
        let calls = Mutex(0)
        server.respond { request in
            guard request.path == "/api/chats" else { return .json(#"{"count": 0}"#) }
            let call = calls.withLock { $0 += 1; return $0 }
            return call == 1 ? Self.page(["a"], hasMore: false) : Self.page(["new", "a"], hasMore: false)
        }
        let model = model()
        await model.open(.init())
        await model.refresh()
        #expect(model.chats.map(\.ref) == ["new", "a"])
    }

    @Test("A failed refresh keeps the rows and shows the error; Retry clears it")
    func failedRefresh() async {
        let failing = Mutex(false)
        server.respond { request in
            guard request.path == "/api/chats" else { return .json(#"{"count": 0}"#) }
            return failing.withLock { $0 }
                ? .json(#"{"detail": "Database not available"}"#, status: 503)
                : Self.page(["a", "b"], hasMore: true)
        }
        let model = model()
        await model.open(.init())
        failing.withLock { $0 = true }
        await model.refresh()
        #expect(model.chats.map(\.ref) == ["a", "b"])
        #expect(model.error == .serverUnavailable(detail: "Database not available"))
        // No paging past an error.
        let asked = server.requests(to: "/api/chats").count
        await model.loadMore()
        #expect(server.requests(to: "/api/chats").count == asked)

        failing.withLock { $0 = false }
        await model.retry()
        #expect(model.error == nil)
        #expect(server.requests(to: "/api/chats").last?.query["offset"] == "2")
    }

    @Test("A failed new search shows no stale rows")
    func failedSearch() async {
        server.respond { request in
            request.query["search"] == nil ? Self.page(["a"], hasMore: false) : .init(failure: .notConnectedToInternet)
        }
        let model = model()
        await model.open(.init())
        await model.open(.init(search: "x"))
        #expect(model.chats.isEmpty)
        #expect(model.error == .transport(.notConnectedToInternet))
    }

    @Test("A 401 ends the session once and shows no error")
    func unauthorized() async {
        server.respond { request in
            request.path == "/api/chats" ? .json(#"{"detail": "Not authenticated"}"#, status: 401) : .json(#"{"count": 3}"#)
        }
        let model = model()
        await model.open(.init(search: "only the list"))
        #expect(recorder.clients.count == 1)
        #expect(recorder.clients.first === model.client)
        #expect(model.error == nil)
    }

    @Test("A failing side request leaves the list alone")
    func sideRequestFailure() async {
        server.respond { request in
            request.path == "/api/chats" ? Self.page(["a"], hasMore: false) : .json("{}", status: 500)
        }
        let model = model()
        await model.open(.init())
        #expect(model.chats.map(\.ref) == ["a"])
        #expect(model.error == nil)
        #expect(model.folders.isEmpty)
        #expect(recorder.clients.isEmpty)
    }

    @Test("Leaving the screen cancels the load and the next open starts again")
    func cancellation() async {
        server.respond { request in
            if request.path == "/api/chats" { Thread.sleep(forTimeInterval: 0.5) }
            return Self.page(["slow"], hasMore: false)
        }
        let model = model()
        let task = Task { await model.open(.init(search: "slow")) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await task.value
        #expect(model.appliedQuery == nil)
        #expect(model.error == nil)
        #expect(!model.isLoading)
        await model.open(.init(search: "slow"))
        #expect(model.chats.map(\.ref) == ["slow"])
    }
}

@MainActor
@Suite("Topic list model")
struct TopicListModelTests {
    private let server = MockServer()
    private let recorder = SessionEndRecorder()

    private func model() -> TopicListModel {
        let client = APIClient(server: server.address, cookie: "topics",
                               configuration: MockServer.configuration(), cache: MockServer.cache())
        return TopicListModel(client: client, ref: "forum-ref") { [recorder] in recorder.record($0) }
    }

    @Test("The demo forum's topics load pinned first, with the closed one marked")
    func loads() async throws {
        server.respond { request in
            request.path == "/api/chats/forum-ref/topics" ? ((try? .fixture("topics")) ?? .init(status: 500)) : .init(status: 404)
        }
        let model = model()
        await model.open()
        #expect(model.topics.map(\.title) == ["Events", "Electronics", "Woodworking", "3D printing", "General"])
        #expect(model.topics.first?.isPinned == true)
        #expect(model.topics.first { $0.title == "Woodworking" }?.isClosed == true)
        #expect(model.loaded)
        await model.open()
        #expect(server.requests.count == 1)
    }

    @Test("Hidden topics are skipped and pinned ones lead, the rest in the server's order")
    func ordering() throws {
        let json = #"""
        {"topics": [
          {"id": 1, "title": "General", "is_closed": 0, "is_pinned": 0, "is_hidden": 0},
          {"id": 2, "title": "Secret", "is_closed": 0, "is_pinned": 1, "is_hidden": 1},
          {"id": 3, "title": "News", "is_closed": 0, "is_pinned": 0, "is_hidden": 0},
          {"id": 4, "title": "Rules", "is_closed": 1, "is_pinned": true, "is_hidden": false}
        ]}
        """#
        let list = try ArchiveDecoder.decode(TopicList.self, from: Data(json.utf8))
        #expect(TopicListModel.visible(list.topics).map(\.id) == [4, 1, 3])
    }

    @Test("A 404 shows that the chat is gone; a 401 ends the session")
    func errors() async {
        server.respond { _ in .json(#"{"detail": "Chat not found"}"#, status: 404) }
        let model = model()
        await model.open()
        #expect(model.error == .notFound)
        #expect(recorder.clients.isEmpty)

        server.respond { _ in .json(#"{"detail": "Not authenticated"}"#, status: 401) }
        await model.load()
        #expect(recorder.clients.count == 1)
    }

    @Test("Topic colours read as RGB, and a missing colour falls back")
    func colours() {
        #expect(TopicRow.color(0xFF0000) == .init(red: 1, green: 0, blue: 0))
        #expect(TopicRow.color(nil) == .accentColor)
        #expect(TopicRow.color(-1) == .accentColor)
    }
}
