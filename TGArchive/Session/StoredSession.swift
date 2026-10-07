import Foundation

/// The one session this install holds, as kept in the Keychain. The password and the share token are never
/// part of it, so the app cannot sign in again on its own.
struct StoredSession: Codable, Hashable, Sendable {
    enum Role: String, Codable, Hashable, Sendable {
        case master, viewer, token, anonymous

        /// The role `/api/auth/check` names; anything unknown is treated as a plain viewer.
        init(serverRole: String?) {
            self = serverRole.flatMap(Role.init(rawValue:)) ?? .viewer
        }
    }

    let server: ServerAddress
    /// The `viewer_auth` value; nil for an anonymous server.
    let cookie: String?
    let cookieExpires: Date?
    let username: String?
    let role: Role
    let noDownload: Bool

    func isExpired(at now: Date) -> Bool {
        guard let cookieExpires else { return false }
        return cookieExpires <= now
    }
}
