import Foundation
import Observation

/// One thread's pages. It opens at the newest page, or at an anchor (a search hit) with the messages before
/// it, then pages older with the date-and-id cursor and, after an anchor, newer by id. One load runs at a
/// time, inside the caller's task, so leaving the screen cancels it.
@MainActor @Observable
final class ChatThreadModel {
    enum Direction: Equatable, Sendable {
        case first, older, newer
    }

    static let pageSize = 50

    let ref: String
    let topicID: Int?
    let anchor: Int?
    private(set) var window = MessageWindow()
    /// The chat's own row: its type decides whether sender names show, its title fills in a missing one.
    private(set) var chat: Chat?
    /// The first page arrived.
    private(set) var loaded = false
    /// The load in flight, if any.
    private(set) var loading: Direction?
    private(set) var error: APIError?
    /// The server answered 404: the chat is unknown or no longer visible to this login.
    private(set) var isUnavailable = false

    @ObservationIgnored let client: APIClient
    /// Told about a 401, the only error that leaves the screen. The view points it at `SessionStore`.
    @ObservationIgnored var sessionEnded: @MainActor (APIClient) async -> Void
    @ObservationIgnored private var failed: Direction?

    init(client: APIClient, ref: String, topicID: Int? = nil, anchor: Int? = nil,
         sessionEnded: @escaping @MainActor (APIClient) async -> Void = { _ in }) {
        self.client = client
        self.ref = ref
        self.topicID = topicID
        self.anchor = anchor
        self.sessionEnded = sessionEnded
    }

    /// Sender names and avatars show in groups and supergroups, never in a private chat or a channel.
    var showsSenders: Bool {
        guard let type = chat?.type else { return false }
        return type != "private" && type != "channel"
    }

    /// Loads the first page once; coming back to the screen keeps what it shows.
    func open() async {
        guard !loaded, loading == nil, !isUnavailable else { return }
        await load(.first)
    }

    /// The page before the oldest message, when the server has one.
    func loadOlder() async {
        guard loaded, window.hasOlder, loading == nil, error == nil else { return }
        await load(.older)
    }

    /// The page after the newest message, in a thread opened at an anchor.
    func loadNewer() async {
        guard loaded, window.hasNewer, loading == nil, error == nil else { return }
        await load(.newer)
    }

    /// Leaves an anchored thread for the newest page.
    func jumpToLatest() async {
        guard loading == nil else { return }
        await load(.first, newest: true)
    }

    /// Repeats the load that failed.
    func retry() async {
        guard loading == nil else { return }
        let direction = failed ?? .first
        error = nil
        await load(direction)
    }

    // MARK: - Loading

    private func load(_ direction: Direction, newest: Bool = false) async {
        loading = direction
        defer { loading = nil }
        do {
            switch direction {
            case .first:
                // An anchor opens on the page that holds it: ids below anchor + 1, newest first.
                var cursor = MessageCursor.newest
                if !newest, !loaded, let anchor { cursor = .beforeID(anchor + 1) }
                let fromAnchor = cursor != .newest
                let needsChat = chat == nil
                async let info: Chat? = needsChat ? optionalChat() : nil
                let page: MessagePage = try await client.get(endpoint(cursor))
                let row = await info
                guard !Task.isCancelled else { return }
                if let row { chat = row }
                window = fromAnchor
                    ? MessageWindow(anchored: page.messages, full: isFull(page))
                    : MessageWindow(newest: page.messages, full: isFull(page))
                loaded = true
            case .older:
                guard let cursor = window.olderCursor else { return }
                let page: MessagePage = try await client.get(endpoint(cursor))
                guard !Task.isCancelled else { return }
                window.addOlder(page.messages, full: isFull(page))
            case .newer:
                guard let cursor = window.newerCursor else { return }
                let page: MessagePage = try await client.get(endpoint(cursor))
                guard !Task.isCancelled else { return }
                window.addNewer(page.messages, full: isFull(page))
            }
            error = nil
            failed = nil
        } catch {
            guard !error.isCancellation, !Task.isCancelled else { return }
            await fail(error, direction: newest ? .first : direction)
        }
    }

    private func fail(_ error: APIError, direction: Direction) async {
        switch error {
        case .unauthorized:
            await sessionEnded(client)
        case .notFound:
            isUnavailable = true
        default:
            self.error = error
            failed = direction
        }
    }

    /// The chat's row, for its type and title. Its failure leaves the thread alone; a 401 or a 404 surfaces
    /// through the messages request made beside it.
    private func optionalChat() async -> Chat? {
        try? await client.get(.chat(ref: ref))
    }

    /// A page as long as asked may have more behind it. Messages that did not decode still count.
    private func isFull(_ page: MessagePage) -> Bool {
        page.messages.count + page.dropped >= Self.pageSize
    }

    private func endpoint(_ cursor: MessageCursor) -> Endpoint {
        .messages(ref: ref, limit: Self.pageSize, cursor: cursor, topicID: topicID)
    }
}
