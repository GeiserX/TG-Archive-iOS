import Foundation
import Observation

/// The Search tab's pages: a word-prefix search across every chat the login sees. Typing waits for a
/// 300 ms pause, the query is trimmed and capped at the server's 500 characters, and the next page loads
/// when the end of the list shows, until the server's offset limit of 5000. One load runs at a time, and
/// every load runs inside the caller's task, so leaving the screen or typing again cancels it.
@MainActor @Observable
final class SearchModel {
    static let pageSize = 20
    /// The server takes 1 to 500 characters, counted as Unicode code points.
    nonisolated static let maxQueryLength = 500
    /// The highest `offset` the server accepts.
    static let maxOffset = 5000
    static let debounce: Duration = .milliseconds(300)

    private(set) var results: [SearchResult] = []
    private(set) var hasMore = false
    /// False when the server has no full-text index, so every search answers empty.
    private(set) var indexed = true
    private(set) var isLoading = false
    private(set) var error: APIError?
    /// The query the shown rows answer, nil before the first search and after the field is cleared.
    private(set) var appliedQuery: String?
    /// The offset of the next page: every row the server sent, repeats included.
    private(set) var nextOffset = 0

    @ObservationIgnored let client: APIClient
    /// Told about a 401, the only error that leaves the screen. The view points it at `SessionStore`.
    @ObservationIgnored var sessionEnded: @MainActor (APIClient) async -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Bumped by every load and by clearing; an answer for an older one is dropped.
    @ObservationIgnored private var generation = 0

    init(client: APIClient, sessionEnded: @escaping @MainActor (APIClient) async -> Void = { _ in }) {
        self.client = client
        self.sessionEnded = sessionEnded
    }

    /// More rows exist and the server still takes the offset they start at.
    var canLoadMore: Bool { hasMore && error == nil && nextOffset <= Self.maxOffset }

    /// More rows exist past the deepest offset the server accepts.
    var reachedOffsetLimit: Bool { hasMore && nextOffset > Self.maxOffset }

    /// The search field changed. A blank field clears the results at once; anything else waits for a pause
    /// in typing, then loads the first page unless that query already shows.
    func search(_ text: String, debounce: Duration = SearchModel.debounce) async {
        guard let query = Self.normalized(text) else {
            clear()
            return
        }
        guard query != appliedQuery || (results.isEmpty && error != nil) else { return }
        if debounce > .zero {
            try? await Task.sleep(for: debounce)
            if Task.isCancelled { return }
        }
        await run { generation in await self.loadFirstPage(query, generation: generation) }
    }

    /// The next page, when the server has one and nothing else is loading.
    func loadMore() async {
        guard canLoadMore, loadTask == nil, let query = appliedQuery else { return }
        let offset = nextOffset
        await run { generation in await self.loadPage(query, offset: offset, generation: generation) }
    }

    /// After an error: the next page when rows show, else the first.
    func retry() async {
        guard let query = appliedQuery else { return }
        error = nil
        if results.isEmpty {
            await run { generation in await self.loadFirstPage(query, generation: generation) }
        } else {
            await loadMore()
        }
    }

    /// The query as sent: trimmed, and cut to the longest run of whole characters within the server's limit.
    /// Nil when nothing is left.
    nonisolated static func normalized(_ text: String) -> String? {
        guard let trimmed = text.nonBlank else { return nil }
        var length = 0
        var end = trimmed.startIndex
        for character in trimmed {
            length += character.unicodeScalars.count
            if length > maxQueryLength { break }
            end = trimmed.index(after: end)
        }
        return String(trimmed[..<end]).nonBlank
    }

    // MARK: - Loading

    private func clear() {
        loadTask?.cancel()
        loadTask = nil
        generation += 1
        results = []
        hasMore = false
        indexed = true
        isLoading = false
        error = nil
        appliedQuery = nil
        nextOffset = 0
    }

    /// Runs one load as the model's only one: it replaces any load in flight and is cancelled with the
    /// caller's task.
    private func run(_ work: @escaping @MainActor (Int) async -> Void) async {
        loadTask?.cancel()
        generation += 1
        let current = generation
        isLoading = true
        let task = Task { await work(current) }
        loadTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if current == generation {
            isLoading = false
            loadTask = nil
        }
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation && !Task.isCancelled
    }

    private func loadFirstPage(_ query: String, generation: Int) async {
        do {
            let page: SearchPage = try await client.get(.search(query: query, limit: Self.pageSize, offset: 0))
            guard isCurrent(generation) else { return }
            results = Self.unique(page.results)
            hasMore = page.hasMore
            indexed = page.indexed
            nextOffset = page.results.count
            appliedQuery = query
            error = nil
        } catch {
            guard isCurrent(generation) else { return }
            // A failed new query shows no rows from the one before.
            if appliedQuery != query {
                results = []
                hasMore = false
                indexed = true
                nextOffset = 0
            }
            appliedQuery = query
            await fail(error)
        }
    }

    private func loadPage(_ query: String, offset: Int, generation: Int) async {
        do {
            let page: SearchPage = try await client.get(.search(query: query, limit: Self.pageSize, offset: offset))
            guard isCurrent(generation), appliedQuery == query else { return }
            let known = Set(results.map(\.key))
            results += Self.unique(page.results).filter { !known.contains($0.key) }
            hasMore = page.hasMore && !page.results.isEmpty
            indexed = page.indexed
            nextOffset = offset + page.results.count
            error = nil
        } catch {
            guard isCurrent(generation) else { return }
            await fail(error)
        }
    }

    private func fail(_ error: APIError) async {
        guard !error.isCancellation else { return }
        if error == .unauthorized {
            await sessionEnded(client)
            return
        }
        self.error = error
    }

    /// Offset paging can repeat a hit when new messages arrive between pages, so each message shows once.
    private static func unique(_ results: [SearchResult]) -> [SearchResult] {
        var seen = Set<SearchResult.Key>()
        return results.filter { seen.insert($0.key).inserted }
    }
}

extension SearchResult {
    /// A message id is unique within its chat only, so a hit is the chat and the id together.
    struct Key: Hashable, Sendable {
        let ref: String
        let id: Int
    }

    var key: Key { Key(ref: chat.ref, id: id) }

    /// Where tapping the hit goes: the chat, opened at the message.
    var route: Route { .chat(ref: chat.ref, title: chat.displayTitle, anchor: id) }
}

extension SearchChat {
    var displayTitle: String {
        ChatTitle.make(title: title, firstName: firstName, lastName: lastName, username: username)
    }
}
