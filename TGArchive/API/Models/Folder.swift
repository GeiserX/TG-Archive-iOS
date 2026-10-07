import Foundation

/// `GET /api/folders`.
struct FolderList: Decodable, Hashable, Sendable {
    let folders: [Folder]
}

struct Folder: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let title: String?
    let emoticon: String?
    /// Counted over the chats this login can see.
    let chatCount: Int?
}
