import Foundation

/// `GET /api/auth/check`. Public, so it also tells whether an address is an archive server at all:
/// the two flags are required, and a body without them is not one.
struct AuthCheck: Decodable, Hashable, Sendable {
    let authenticated: Bool
    let authRequired: Bool
    /// `master`, `viewer` or `token`.
    let role: String?
    let username: String?
    let noDownload: Bool?
    /// No login mode is configured on the server.
    let setupRequired: Bool?
    /// The server signs people in through a proxy identity header, which this app does not support.
    let proxyAuth: Bool?
}
