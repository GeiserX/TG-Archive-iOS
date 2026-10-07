import Foundation
import Observation

/// Settings' state: the archive figures, and the sign-out and clear-cache actions.
@MainActor @Observable
final class SettingsModel {
    private(set) var stats: ArchiveStats?
    private(set) var error: APIError?
    private(set) var isSigningOut = false
    /// Set after Clear cache, so the row can say it is done.
    private(set) var cacheCleared = false

    /// `GET /api/stats`. A 401 means the session ended on the server; anything else is a banner.
    func load(_ session: Session, store: SessionStore) async {
        do {
            let stats: ArchiveStats = try await session.client.get(.stats)
            self.stats = stats
            error = nil
        } catch {
            if error == .unauthorized {
                await store.sessionEnded(session.client)
            } else if !error.isCancellation {
                self.error = error
            }
        }
    }

    /// The Archive section shows only when the server's owner allows it.
    var visibleStats: ArchiveStats? {
        guard let stats, stats.showStats == true else { return nil }
        return stats
    }

    func signOut(using store: SessionStore) async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await store.signOut()
    }

    /// Drops the media, thumbnails, decoded images and downloaded files kept on the device. They download
    /// again, and the session stays.
    func clearCache(_ session: Session, store: SessionStore) async {
        session.client.cache.removeAllCachedResponses()
        await MediaLoader.current(for: session, in: store).purge()
        FileStore.shared.wipe()
        cacheCleared = true
    }

    // MARK: - Labels

    /// "Owner", "Viewer", "Share link “Hike photos”" or "Open server".
    static func roleLabel(for stored: StoredSession) -> String {
        switch stored.role {
        case .master: String(localized: "settings.role.master")
        case .viewer: String(localized: "settings.role.viewer")
        case .anonymous: String(localized: "settings.role.anonymous")
        case .token:
            if let name = shareLinkName(stored.username) {
                String(localized: "settings.role.token.named \(name)")
            } else {
                String(localized: "settings.role.token")
            }
        }
    }

    /// The account name to show next to the role. A share link has none: the server names it `token:<label>`,
    /// and the label is already part of the role.
    static func accountName(for stored: StoredSession) -> String? {
        switch stored.role {
        case .master, .viewer: stored.username.flatMap { $0.isEmpty ? nil : $0 }
        case .token, .anonymous: nil
        }
    }

    /// The label the owner gave a share link, from the `token:<label>` username the server reports.
    static func shareLinkName(_ username: String?) -> String? {
        guard var name = username else { return nil }
        if name.hasPrefix("token:") { name.removeFirst("token:".count) }
        name = name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }
}
