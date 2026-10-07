import Foundation
import Observation

/// The chat list's pages: the first page on open, the next one when the end of the list shows, and the
/// first again on pull to refresh, a new search or a folder change. One load runs at a time, and every load
/// runs inside the caller's task, so leaving the screen cancels it.
@MainActor @Observable
final class ChatListModel {
    /// What the list shows: the server-side title search and the folder filter.
    struct Query: Hashable, Sendable {
        var search = ""
        var folderID: Int?
    }

    static let pageSize = 50

    let archived: Bool
    private(set) var chats: [Chat] = []
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var error: APIError?
    /// The "Archived (n)" row; zero hides it. Only the main list asks.
    private(set) var archivedCount = 0
    /// The folders for the toolbar menu; empty hides it. Only the main list asks.
    private(set) var folders: [Folder] = []
    /// The query the shown rows answer, nil before the first load.
    private(set) var appliedQuery: Query?

    @ObservationIgnored let client: APIClient
    /// Told about a 401, the only error that leaves the screen. The view points it at `SessionStore`.
    @ObservationIgnored var sessionEnded: @MainActor (APIClient) async -> Void
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// Bumped by every load; an answer for an older one is dropped.
    @ObservationIgnored private var generation = 0

    init(client: APIClient, archived: Bool = false,
         sessionEnded: @escaping @MainActor (APIClient) async -> Void = { _ in }) {
        self.client = client
        self.archived = archived
        self.sessionEnded = sessionEnded
    }

    /// Loads the first page for `query` unless it already shows, so coming back to the list keeps its
    /// pages and its scroll position.
    func open(_ query: Query) async {
        let query = Query(search: query.search.nonBlank ?? "", folderID: archived ? nil : query.folderID)
        guard query != appliedQuery || (chats.isEmpty && error != nil) else { return }
        await run { generation in await self.loadFirstPage(query, generation: generation) }
    }

    /// Pull to refresh: the first page again, with the archived count and the folders.
    func refresh() async {
        let query = appliedQuery ?? Query()
        await run { generation in await self.loadFirstPage(query, generation: generation) }
    }

    /// The next page, when the server has one and nothing else is loading.
    func loadMore() async {
        guard hasMore, loadTask == nil, error == nil, let query = appliedQuery else { return }
        let offset = chats.count
        await run { generation in await self.loadPage(query, offset: offset, generation: generation) }
    }

    /// After an error: the next page when rows show, else the first.
    func retry() async {
        let query = appliedQuery ?? Query()
        error = nil
        if chats.isEmpty {
            await run { generation in await self.loadFirstPage(query, generation: generation) }
        } else {
            let offset = chats.count
            await run { generation in await self.loadPage(query, offset: offset, generation: generation) }
        }
    }

    // MARK: - Loading

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

    private func loadFirstPage(_ query: Query, generation: Int) async {
        // The archived count and the folders ride along with the unfiltered main list.
        let sideLoads = !archived && query == Query()
        async let page: ChatsPage = client.get(endpoint(query, offset: 0))
        async let count: ArchivedCount? = sideLoads ? optional(.archivedCount) : nil
        async let folderList: FolderList? = sideLoads ? optional(.folders) : nil
        do {
            let first = try await page
            let (counted, listed) = await (count, folderList)
            guard isCurrent(generation) else { return }
            chats = Self.unique(first.chats)
            hasMore = first.hasMore
            appliedQuery = query
            error = nil
            if let counted { archivedCount = counted.count }
            if let listed { folders = listed.folders }
        } catch {
            _ = await (count, folderList)
            guard isCurrent(generation) else { return }
            // A failed refresh keeps the rows it would have replaced; a failed new query shows none.
            if appliedQuery != query {
                chats = []
                hasMore = false
            }
            appliedQuery = query
            await fail(error as? APIError ?? APIError.from(transport: error))
        }
    }

    private func loadPage(_ query: Query, offset: Int, generation: Int) async {
        do {
            let page: ChatsPage = try await client.get(endpoint(query, offset: offset))
            guard isCurrent(generation), appliedQuery == query else { return }
            let known = Set(chats.map(\.ref))
            chats += Self.unique(page.chats).filter { !known.contains($0.ref) }
            hasMore = page.hasMore
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

    /// A side request whose failure leaves the list alone; a 401 still ends the session.
    private func optional<T: Decodable & Sendable>(_ endpoint: Endpoint) async -> T? {
        do {
            return try await client.get(endpoint)
        } catch {
            if error == .unauthorized { await sessionEnded(client) }
            return nil
        }
    }

    private func endpoint(_ query: Query, offset: Int) -> Endpoint {
        .chats(limit: Self.pageSize, offset: offset, search: query.search.isEmpty ? nil : query.search,
               archived: archived, folderID: query.folderID)
    }

    /// Offset paging can repeat a row when the list moves between pages, so a ref shows once. Rows with
    /// different refs are never merged: a chat several accounts hold is already one row.
    private static func unique(_ chats: [Chat]) -> [Chat] {
        var seen = Set<String>()
        return chats.filter { seen.insert($0.ref).inserted }
    }
}
