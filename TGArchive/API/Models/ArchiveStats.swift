import Foundation

/// `GET /api/stats`, the parts Settings shows. For a restricted login the counts cover only its chats.
struct ArchiveStats: Decodable, Hashable, Sendable {
    let chats: Int?
    let messages: Int?
    let mediaFiles: Int?
    let lastBackupTime: Date?
    /// Whether the server's owner lets the archive figures be shown.
    let showStats: Bool?
}

/// `GET /api/health`.
struct Health: Decodable, Hashable, Sendable {
    let status: String?
    let database: String?
}
