import Foundation

/// `GET /api/chats`.
struct ChatsPage: Decodable, Hashable, Sendable {
    let chats: [Chat]
    let total: Int?
    @FlexBool var hasMore: Bool
}

/// A chat list row, and `GET /api/chats/{ref}` (the same shape without `preview`). `ref` is opaque and is
/// the only way the app addresses a chat.
struct Chat: Decodable, Hashable, Sendable, Identifiable {
    let ref: String
    /// `private`, `group`, `supergroup` or `channel`.
    let type: String?
    let title: String?
    let firstName: String?
    let lastName: String?
    let username: String?
    @FlexBool var isForum: Bool
    @FlexBool var isArchived: Bool
    /// The archive's accounts that hold this chat; a shared channel is listed once with several.
    let accounts: [Int]?
    /// Root-absolute path from the server; the app builds avatar URLs itself through `Endpoint.avatar(ref:)`.
    let avatarURL: String?
    @Lenient var preview: ChatPreview?

    var id: String { ref }

    private enum CodingKeys: String, CodingKey {
        case ref, type, title, firstName, lastName, username, isForum, isArchived, accounts, preview
        case avatarURL = "avatarUrl"
    }
}

/// The chat's newest message not deleted in Telegram, for the list's second line.
struct ChatPreview: Decodable, Hashable, Sendable {
    let messageID: Int
    let date: Date
    /// One line, cut to 100 characters; nil when the message has no text.
    let text: String?
    /// `You`, a first name, or nil (channels, the other side of a private chat, service rows).
    let sender: String?
    /// `text`, `service`, `poll`, a media type, or `message`.
    let kind: String?
    @FlexBool var outgoing: Bool
    /// For an old service row with no stored sentence: its `action_type` and `new_title`.
    let action: String?
    let actionTitle: String?

    private enum CodingKeys: String, CodingKey {
        case messageID = "messageId"
        case date, text, sender, kind, outgoing, action, actionTitle
    }
}

/// `GET /api/archived/count`.
struct ArchivedCount: Decodable, Hashable, Sendable {
    let count: Int
}
