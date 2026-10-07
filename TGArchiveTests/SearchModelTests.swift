import Foundation
import Synchronization
import Testing
@testable import TGArchive

@MainActor
@Suite("Search model")
struct SearchModelTests {
    private let server = MockServer()
    private let recorder = SessionEndRecorder()

    private func model() -> SearchModel {
        let client = APIClient(server: server.address, cookie: "search-session",
                               configuration: MockServer.configuration(), cache: MockServer.cache())
        return SearchModel(client: client) { [recorder] in recorder.record($0) }
    }

    /// A search page with one hit per `(ref, id)`.
    private nonisolated static func page(_ hits: [(String, Int)], hasMore: Bool, indexed: Bool = true)
        -> MockServer.Response {
        let rows = hits.map { ref, id in
            #"{"id": \#(id), "date": "2026-10-01T10:00:00", "text": "hit \#(id)", "sender_name": null, "#
                + #""sender_account_id": null, "is_deleted": false, "topic_title": null, "matched_in": "message", "#
                + #""chat": {"ref": "\#(ref)", "title": "Chat \#(ref)", "type": "group", "is_forum": false, "#
                + #""avatar_url": null}}"#
        }
        return .json(#"{"query": "q", "limit": 20, "offset": 0, "has_more": \#(hasMore), "#
            + #""indexed": \#(indexed), "results": [\#(rows.joined(separator: ","))]}"#)
    }

    private var searches: [MockServer.Recorded] { server.requests(to: "/api/search/messages") }

    @Test("A search sends the trimmed query with 20 per page and shows the demo archive's hits")
    func firstPage() async throws {
        server.respond { _ in (try? .fixture("search")) ?? .init(status: 500) }
        let model = model()
        await model.search("  the ", debounce: .zero)

        let request = try #require(searches.first)
        #expect(request.query == ["q": "the", "limit": "20", "offset": "0"])
        #expect(request.cookie == "viewer_auth=search-session")
        #expect(model.results.count == 20)
        #expect(model.results.first?.chat.displayTitle == "Weekend Hikers")
        #expect(model.results.first?.isDeleted == true)
        #expect(model.hasMore)
        #expect(model.indexed)
        #expect(model.appliedQuery == "the")
        #expect(model.nextOffset == 20)
        #expect(model.error == nil)
        #expect(!model.isLoading)
    }

    @Test("Forum hits carry their topic, and a hit opens its chat at the message")
    func forumHitRoute() async throws {
        server.respond { _ in (try? .fixture("search-topics")) ?? .init(status: 500) }
        let model = model()
        await model.search("solder", debounce: .zero)
        let hit = try #require(model.results.first)
        #expect(hit.topicTitle == "Woodworking")
        #expect(hit.chat.isForum)
        #expect(hit.route == .chat(ref: "UtB4DrfIxOJyfIL1mRcO0w", title: "Maker Space", topicID: nil, anchor: 36))
        #expect(!model.hasMore)
        #expect(!model.canLoadMore)
    }

    @Test("A private chat's hit is titled by the person's name")
    func privateChatTitle() throws {
        let json = #"{"ref": "p", "title": null, "first_name": "Mirela", "last_name": "Pinecrest", "#
            + #""username": "mirela", "type": "private", "is_forum": 0, "avatar_url": null}"#
        let chat = try ArchiveDecoder.decode(SearchChat.self, from: Data(json.utf8))
        #expect(chat.displayTitle == "Mirela Pinecrest")
    }

    @Test("Typing waits 300 ms, and a keystroke within the pause replaces the search")
    func debounce() async throws {
        server.respond { _ in Self.page([("a", 1)], hasMore: false) }
        let model = model()
        let first = Task { await model.search("so") }
        try await Task.sleep(for: .milliseconds(150))
        #expect(searches.isEmpty)
        first.cancel()
        await first.value
        #expect(searches.isEmpty)

        let start = ContinuousClock.now
        await model.search("sol")
        #expect(ContinuousClock.now - start >= .milliseconds(300))
        #expect(searches.map { $0.query["q"] } == ["sol"])
        #expect(model.appliedQuery == "sol")
    }

    @Test("Clearing the field empties the list at once, without a request, and drops a search in flight")
    func clearing() async throws {
        server.respond { request in
            if request.query["q"] == "slow" { Thread.sleep(forTimeInterval: 0.5) }
            return Self.page([("a", 1)], hasMore: true)
        }
        let model = model()
        await model.search("fast", debounce: .zero)
        #expect(model.results.count == 1)

        let slow = Task { await model.search("slow", debounce: .zero) }
        try await Task.sleep(for: .milliseconds(100))
        await model.search("   ")
        #expect(model.results.isEmpty)
        #expect(model.appliedQuery == nil)
        #expect(!model.hasMore)
        #expect(!model.isLoading)
        await slow.value
        #expect(model.results.isEmpty)
        #expect(model.appliedQuery == nil)
        #expect(model.error == nil)
        #expect(searches.count == 2)
    }

    @Test("The same query again keeps the results instead of asking the server")
    func sameQuery() async {
        server.respond { _ in Self.page([("a", 1)], hasMore: false) }
        let model = model()
        await model.search("walk", debounce: .zero)
        await model.search(" walk ")
        #expect(searches.count == 1)
    }

    @Test("A query is cut to 500 code points without splitting a character", arguments: [
        (String(repeating: "a", count: 600), String(repeating: "a", count: 500)),
        // The family emoji is one character of five code points: 99 fit, the 100th would make 500 + 5.
        (String(repeating: "x", count: 5) + String(repeating: "👨‍👩‍👧", count: 120),
         String(repeating: "x", count: 5) + String(repeating: "👨‍👩‍👧", count: 99)),
        ("short", "short"),
    ])
    func queryLength(input: String, sent: String) async throws {
        #expect(SearchModel.normalized(input) == sent)
        #expect(sent.unicodeScalars.count <= 500)
        server.respond { _ in Self.page([], hasMore: false) }
        let model = model()
        await model.search(input, debounce: .zero)
        #expect(try #require(searches.first).query["q"] == sent)
    }

    @Test("Blank input is no query")
    func blank() {
        #expect(SearchModel.normalized("") == nil)
        #expect(SearchModel.normalized(" \n\t ") == nil)
    }

    @Test("Pages follow the rows the server sent, and a message repeated across pages shows once")
    func paging() async {
        server.respond { request in
            switch request.query["offset"] {
            // The same message id in two chats is two hits.
            case "0": Self.page([("a", 1), ("b", 1)], hasMore: true)
            case "2": Self.page([("b", 1), ("a", 2)], hasMore: false)
            default: .init(status: 500)
            }
        }
        let model = model()
        await model.search("q", debounce: .zero)
        await model.loadMore()
        #expect(searches.map { $0.query["offset"] } == ["0", "2"])
        #expect(model.results.map(\.key) == [.init(ref: "a", id: 1), .init(ref: "b", id: 1), .init(ref: "a", id: 2)])
        #expect(model.nextOffset == 4)
        #expect(!model.hasMore)
        await model.loadMore()
        #expect(searches.count == 2)
    }

    @Test("Paging stops at the server's offset limit of 5000 and says there is more")
    func offsetLimit() async {
        // 100 rows a page reach the limit in 51 requests; the model never asks past offset 5000.
        server.respond { request in
            let offset = Int(request.query["offset"] ?? "") ?? -1
            guard (0...5000).contains(offset) else { return .json(#"{"detail": "bad offset"}"#, status: 422) }
            return Self.page((offset..<offset + 100).map { ("c", $0) }, hasMore: true)
        }
        let model = model()
        await model.search("q", debounce: .zero)
        while model.canLoadMore { await model.loadMore() }
        #expect(searches.last?.query["offset"] == "5000")
        #expect(searches.count == 51)
        #expect(model.results.count == 5100)
        #expect(model.reachedOffsetLimit)
        #expect(model.error == nil)
        await model.loadMore()
        #expect(searches.count == 51)
    }

    @Test("An empty page that claims more ends the paging")
    func emptyPageEnds() async {
        server.respond { request in
            request.query["offset"] == "0" ? Self.page([("a", 1)], hasMore: true) : Self.page([], hasMore: true)
        }
        let model = model()
        await model.search("q", debounce: .zero)
        await model.loadMore()
        #expect(!model.hasMore)
        #expect(!model.canLoadMore)
        #expect(!model.reachedOffsetLimit)
    }

    @Test("A server without the search index answers indexed false, which the screen shows")
    func notIndexed() async {
        server.respond { _ in Self.page([], hasMore: false, indexed: false) }
        let model = model()
        await model.search("q", debounce: .zero)
        #expect(!model.indexed)
        #expect(model.results.isEmpty)
        #expect(model.appliedQuery == "q")
        await model.search("")
        #expect(model.indexed)
    }

    @Test("A failed new search shows no stale rows; Retry asks again")
    func failedSearch() async {
        let failing = Mutex(false)
        server.respond { request in
            failing.withLock { $0 } ? .init(failure: .notConnectedToInternet) : Self.page([("a", 1)], hasMore: false)
        }
        let model = model()
        await model.search("one", debounce: .zero)
        failing.withLock { $0 = true }
        await model.search("two", debounce: .zero)
        #expect(model.results.isEmpty)
        #expect(model.error == .transport(.notConnectedToInternet))
        #expect(model.appliedQuery == "two")

        failing.withLock { $0 = false }
        await model.retry()
        #expect(model.error == nil)
        #expect(model.results.count == 1)
        #expect(searches.last?.query["q"] == "two")
        #expect(searches.last?.query["offset"] == "0")
    }

    @Test("A failed next page keeps the rows; Retry resumes at the same offset")
    func failedPage() async {
        server.respond { request in
            request.query["offset"] == "0"
                ? Self.page([("a", 1), ("a", 2)], hasMore: true)
                : .json(#"{"detail": "Database temporarily unavailable"}"#, status: 503)
        }
        let model = model()
        await model.search("q", debounce: .zero)
        await model.loadMore()
        #expect(model.results.count == 2)
        #expect(model.error == .serverUnavailable(detail: "Database temporarily unavailable"))
        #expect(!model.canLoadMore)

        server.respond { _ in Self.page([("a", 3)], hasMore: false) }
        await model.retry()
        #expect(searches.last?.query["offset"] == "2")
        #expect(model.results.count == 3)
        #expect(model.error == nil)
    }

    @Test("A 401 ends the session once and shows no error")
    func unauthorized() async {
        server.respond { _ in .json(#"{"detail": "Not authenticated"}"#, status: 401) }
        let model = model()
        await model.search("q", debounce: .zero)
        #expect(recorder.clients.count == 1)
        #expect(recorder.clients.first === model.client)
        #expect(model.error == nil)
    }
}

@Suite("Search snippet")
struct SearchSnippetTests {
    @Test("Words that start with a query word are marked, and nothing inside a word")
    func wordPrefix() {
        let snippet = SearchSnippet("Who left the soldering iron on? It's off now.", query: "solder")
        #expect(snippet.markedWords == ["soldering"])
        #expect(SearchSnippet("Who left the soldering iron on?", query: "older").marks.isEmpty)
    }

    @Test("Case and diacritics do not matter, either way round")
    func folding() {
        #expect(SearchSnippet("The paid lot by the Café.", query: "cafe").markedWords == ["Café"])
        #expect(SearchSnippet("Nos vemos en el cafe", query: "CAFÉ").markedWords == ["cafe"])
    }

    @Test("Every query word marks its own words; punctuation and underscores split words as the index does")
    func severalWords() {
        let snippet = SearchSnippet("North lot at 7:30, carpool_list in the sheet", query: "north list 7")
        #expect(snippet.markedWords == ["North", "7", "list"])
    }

    @Test("A query without a word marks nothing and keeps the start of the text")
    func noWords() {
        let snippet = SearchSnippet("Same sun from the summit 🌞", query: "🌞 !!")
        #expect(snippet.marks.isEmpty)
        #expect(snippet.text == "Same sun from the summit 🌞")
    }

    @Test("Whitespace folds to single spaces")
    func whitespace() {
        #expect(SearchSnippet("one\n\n  two\tthree", query: "two").text == "one two three")
    }

    @Test("A late match moves the window so it shows, with ellipses where text was cut")
    func window() throws {
        let filler = String(repeating: "filler ", count: 30)
        let snippet = SearchSnippet(filler + "target word " + filler, query: "target")
        #expect(snippet.text.hasPrefix("…"))
        #expect(snippet.text.hasSuffix("…"))
        #expect(snippet.text.count == SearchSnippet.window + 2)
        #expect(snippet.markedWords == ["target"])
        let mark = try #require(snippet.marks.first)
        #expect(snippet.text.distance(from: snippet.text.startIndex, to: mark.lowerBound) == SearchSnippet.context + 1)
    }

    @Test("An early match keeps the start of the text")
    func earlyMatch() {
        let snippet = SearchSnippet("target " + String(repeating: "x", count: 300), query: "target")
        #expect(!snippet.text.hasPrefix("…"))
        #expect(snippet.text.hasSuffix("…"))
        #expect(snippet.markedWords == ["target"])
    }

    @Test("The row marks exactly the matched words")
    @MainActor
    func attributed() {
        let text = SearchRow.attributed(SearchSnippet("Who left the soldering iron on?", query: "solder"))
        let marked = text.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }
            .map { String(text[$0.range].characters) }
        #expect(marked == ["soldering"])
        #expect(String(text.characters) == "Who left the soldering iron on?")
    }
}
