import Foundation
@testable import TGArchive

/// A fake archive server for the onboarding and settings tests, answering with the fixtures captured from the
/// demo server. It signs anyone in with the cookie `fake-session` and accepts that cookie only.
enum FakeArchive {
    static let cookie = "fake-session"
    static let setCookie = "viewer_auth=fake-session; expires=Fri, 06 Nov 2026 14:00:00 GMT; HttpOnly; "
        + "Max-Age=2592000; Path=/; SameSite=lax"

    /// A server behind a reverse proxy at this path answers under it, as `MockServer(prefix:)` sets up.
    static let prefix = "/archive"

    /// `signedIn` is the auth-check fixture a session with the cookie gets: `auth-check` (owner),
    /// `auth-check-token` (share link with downloads off).
    static func handler(signedIn: String = "auth-check", login: String = "login",
                        stats: MockServer.Response? = nil) -> MockServer.Handler {
        { request in
            let signedInCookie = request.cookie == "viewer_auth=\(cookie)"
            do {
                let path = request.path.hasPrefix(prefix + "/") ? String(request.path.dropFirst(prefix.count)) : request.path
                switch (request.method, path) {
                case ("GET", "/api/auth/check"):
                    return try .fixture(signedInCookie ? signedIn : "auth-check-signed-out")
                case ("POST", "/api/login"):
                    return try .fixture(login, headers: ["Set-Cookie": setCookie])
                case ("POST", "/auth/token"):
                    return try .fixture("token-login", headers: ["Set-Cookie": setCookie])
                case ("POST", "/api/logout"):
                    return try .fixture("logout")
                case ("GET", "/api/stats"):
                    guard signedInCookie else { return try .fixture("error-401", status: 401) }
                    return try stats ?? .fixture("stats")
                default:
                    return try .fixture("error-404", status: 404)
                }
            } catch {
                return MockServer.Response(status: 599)
            }
        }
    }

    /// A store wired to the mock servers, an in-memory vault and a throwaway defaults suite, past first launch.
    @MainActor
    static func store(vault: MemoryVault, cache: URLCache = MockServer.cache()) -> SessionStore {
        let suite = "tgarchive.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "installMarker")
        return SessionStore(vault: vault, defaults: defaults, configuration: MockServer.configuration(), cache: cache)
    }
}
