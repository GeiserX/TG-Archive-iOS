import Foundation

/// Every screen the Chats and Search stacks push. Values only, so a path survives being rebuilt.
enum Route: Hashable, Sendable {
    /// A thread. `topicID` opens one forum topic; `anchor` opens the thread at a message (a search hit).
    case chat(ref: String, title: String? = nil, topicID: Int? = nil, anchor: Int? = nil)
    /// The topics of a forum chat.
    case topics(ref: String, title: String)
    /// The archived chats: the same list with `archived=true`.
    case archived
}
