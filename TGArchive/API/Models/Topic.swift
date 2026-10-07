import Foundation

/// `GET /api/chats/{ref}/topics`.
struct TopicList: Decodable, Hashable, Sendable {
    let topics: [Topic]
}

/// A forum topic.
struct Topic: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let title: String?
    let iconEmoji: String?
    /// An RGB colour as an integer, for the glyph of a topic without an emoji.
    let iconColor: Int?
    @FlexBool var isClosed: Bool
    @FlexBool var isPinned: Bool
    @FlexBool var isHidden: Bool
    let messageCount: Int?
    let lastMessageDate: Date?
}
