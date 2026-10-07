import Foundation

/// `POST /api/login`, `POST /auth/token` and `POST /api/logout`. A 200 from `/api/login` with `message` and no
/// cookie means the server runs in anonymous mode.
struct LoginResponse: Decodable, Hashable, Sendable {
    let success: Bool?
    let role: String?
    let username: String?
    let noDownload: Bool?
    let message: String?
}

/// The body of `POST /api/login`.
struct LoginBody: Encodable, Sendable {
    let username: String
    let password: String
}

/// The body of `POST /auth/token`.
struct TokenBody: Encodable, Sendable {
    let token: String
}
