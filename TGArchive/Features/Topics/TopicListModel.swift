import Foundation
import Observation

/// The topics of one forum chat: pinned first, hidden ones left out, the server's order otherwise.
@MainActor @Observable
final class TopicListModel {
    let ref: String
    private(set) var topics: [Topic] = []
    private(set) var isLoading = false
    private(set) var error: APIError?
    private(set) var loaded = false

    @ObservationIgnored let client: APIClient
    @ObservationIgnored var sessionEnded: @MainActor (APIClient) async -> Void

    init(client: APIClient, ref: String, sessionEnded: @escaping @MainActor (APIClient) async -> Void = { _ in }) {
        self.client = client
        self.ref = ref
        self.sessionEnded = sessionEnded
    }

    /// Loads once; coming back to the screen keeps what it shows.
    func open() async {
        guard !loaded || error != nil else { return }
        await load()
    }

    /// Runs inside the caller's task (`.task`, `.refreshable`), so leaving the screen cancels it.
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let list: TopicList = try await client.get(.topics(ref: ref))
            guard !Task.isCancelled else { return }
            topics = Self.visible(list.topics)
            error = nil
            loaded = true
        } catch {
            guard !error.isCancellation, !Task.isCancelled else { return }
            if error == .unauthorized {
                await sessionEnded(client)
                return
            }
            self.error = error
        }
    }

    /// Hidden topics are skipped; pinned ones come first; the rest keep the server's order.
    static func visible(_ topics: [Topic]) -> [Topic] {
        let shown = topics.filter { !$0.isHidden }
        return shown.filter(\.isPinned) + shown.filter { !$0.isPinned }
    }
}
