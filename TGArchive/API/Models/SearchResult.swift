import Foundation

/// `GET /api/search/messages`.
struct SearchPage: Decodable, Hashable, Sendable {
    @FlexBool var hasMore: Bool
    /// False while the server is still building its search index.
    @FlexBool var indexed: Bool
    let results: [SearchResult]
}

struct SearchResult: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let date: Date
    let text: String?
    let senderName: String?
    @FlexBool var isDeleted: Bool
    let topicTitle: String?
    let matchedIn: String?
    let chat: SearchChat
}

/// The chat a search hit belongs to.
struct SearchChat: Decodable, Hashable, Sendable {
    let ref: String
    let title: String?
    let firstName: String?
    let lastName: String?
    let username: String?
    let type: String?
    @FlexBool var isForum: Bool
    let avatarURL: String?

    private enum CodingKeys: String, CodingKey {
        case ref, title, firstName, lastName, username, type, isForum
        case avatarURL = "avatarUrl"
    }
}
