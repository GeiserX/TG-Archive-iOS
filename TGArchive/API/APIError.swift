import Foundation

/// Every way a call to the archive server can fail, mapped from the status code and the `{"detail": ...}` body.
enum APIError: Error, Equatable, Sendable {
    /// 401. On a login route: wrong credentials or link. On any other route: the session ended on the server.
    case unauthorized
    /// 403. Downloads are off for this login (media), or a master route (never called).
    case forbidden(detail: String?)
    /// 404. Unknown chat, a chat this login no longer sees, or no thumbnail for the file.
    case notFound
    /// 429. The shared login rate limit, 15 attempts per client IP in 5 minutes. Never retried.
    case rateLimited
    /// 400 or 422. A bad parameter or body.
    case badRequest(detail: String?)
    /// 503 (database unreachable, no login mode configured), or 500 `Database not available` from `/auth/token`.
    case serverUnavailable(detail: String?)
    /// Any other status.
    case server(status: Int, detail: String?)
    /// The address answers, but not as a Telegram-Archive server.
    case notAnArchiveServer
    /// No answer: offline, timed out, refused, blocked by App Transport Security, or cancelled.
    case transport(URLError.Code)
    /// The answer did not decode. Carries the coding path, never the payload.
    case decoding(String)

    /// Maps a non-2xx answer.
    static func from(status: Int, body: Data) -> APIError {
        let detail = (try? JSONDecoder().decode(ErrorBody.self, from: body))?.detail
        switch status {
        case 400, 422: return .badRequest(detail: detail)
        case 401: return .unauthorized
        case 403: return .forbidden(detail: detail)
        case 404: return .notFound
        case 429: return .rateLimited
        case 503: return .serverUnavailable(detail: detail)
        case 500 where detail == "Database not available": return .serverUnavailable(detail: detail)
        default: return .server(status: status, detail: detail)
        }
    }

    /// Maps a failure of the request itself.
    static func from(transport error: any Error) -> APIError {
        if let urlError = error as? URLError { return .transport(urlError.code) }
        if error is CancellationError { return .transport(.cancelled) }
        return .transport(.unknown)
    }

    var isCancellation: Bool { self == .transport(.cancelled) }

    /// One localized sentence per case, for the error banner.
    var message: String {
        switch self {
        case .unauthorized:
            String(localized: "api.error.unauthorized")
        case .forbidden:
            String(localized: "api.error.forbidden")
        case .notFound:
            String(localized: "api.error.notFound")
        case .rateLimited:
            String(localized: "api.error.rateLimited")
        case .badRequest:
            String(localized: "api.error.badRequest")
        case let .serverUnavailable(detail):
            detail?.localizedCaseInsensitiveContains("not configured") == true
                ? String(localized: "api.error.setupRequired")
                : String(localized: "api.error.serverUnavailable")
        case let .server(status, _):
            String(localized: "api.error.server \(status)")
        case .notAnArchiveServer:
            String(localized: "api.error.notAnArchiveServer")
        case .transport(.appTransportSecurityRequiresSecureConnection):
            String(localized: "api.error.httpsRequired")
        case .transport(.cancelled):
            String(localized: "api.error.cancelled")
        case .transport(.timedOut):
            String(localized: "api.error.timedOut")
        case .transport(.serverCertificateUntrusted), .transport(.serverCertificateHasBadDate),
             .transport(.serverCertificateHasUnknownRoot), .transport(.serverCertificateNotYetValid),
             .transport(.secureConnectionFailed):
            String(localized: "api.error.certificate")
        case .transport:
            String(localized: "api.error.offline")
        case .decoding:
            String(localized: "api.error.decoding")
        }
    }
}

/// The body of every error answer. FastAPI's validation errors carry a list instead of a string; that reads
/// as no detail.
struct ErrorBody: Decodable, Sendable {
    let detail: String?

    private enum CodingKeys: String, CodingKey { case detail }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        detail = try? container.decodeIfPresent(String.self, forKey: .detail)
    }
}
