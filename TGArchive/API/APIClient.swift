import Foundation
import os

/// Talks to one archive server for one session. Immutable, so any task may use it.
///
/// It never shares cookies with the system: the session cookie is sent as an explicit `Cookie` header on
/// every request, and `Set-Cookie` is read from the login answers by hand. A `Secure` cookie therefore still
/// works against a plain-http server on the local network, and `HTTPCookieStorage.shared` never holds it.
final class APIClient: Sendable {
    static let cookieName = "viewer_auth"

    /// Media, thumbnails and avatars, kept by the system and revalidated on every reuse.
    static let sharedCache = URLCache(
        memoryCapacity: 20 * 1024 * 1024,
        diskCapacity: 300 * 1024 * 1024,
        directory: URL.cachesDirectory.appending(path: "TGArchiveHTTP", directoryHint: .isDirectory)
    )

    let server: ServerAddress
    /// The `viewer_auth` value, or nil for an anonymous server and before sign-in.
    let cookie: String?
    let cache: URLCache
    /// Shared with the media loader, so images use the same cache and the same cookie rules.
    let urlSession: URLSession

    private static let log = Logger(subsystem: "io.github.geiserx.tgarchive", category: "api")

    init(server: ServerAddress, cookie: String?, configuration: URLSessionConfiguration = .default,
         cache: URLCache = APIClient.sharedCache) {
        self.server = server
        self.cookie = cookie
        self.cache = cache
        // swiftlint:disable:next force_cast
        let config = configuration.copy() as! URLSessionConfiguration
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 30
        config.urlCache = cache
        config.requestCachePolicy = .useProtocolCachePolicy
        urlSession = URLSession(configuration: config)
    }

    /// The request for an endpoint with the session cookie attached. The media loader uses it too.
    func request(for endpoint: Endpoint) -> URLRequest {
        var request = endpoint.request(base: server.baseURL)
        if let cookie {
            request.setValue("\(Self.cookieName)=\(cookie)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    func get<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws(APIError) -> T {
        let (data, _) = try await send(request(for: endpoint), endpoint: endpoint)
        return try decode(T.self, from: data)
    }

    /// A JSON POST. Returns the answer and the `viewer_auth` cookie it set, if any.
    func post<T: Decodable & Sendable>(_ endpoint: Endpoint, body: some Encodable & Sendable)
        async throws(APIError) -> (value: T, setCookie: HTTPCookie?) {
        var request = request(for: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw .decoding("request body did not encode")
        }
        let (data, response) = try await send(request, endpoint: endpoint)
        let value = try decode(T.self, from: data)
        return (value, Self.sessionCookie(in: response))
    }

    /// The bytes of a media route.
    func data(for endpoint: Endpoint) async throws(APIError) -> Data {
        try await send(request(for: endpoint), endpoint: endpoint).0
    }

    /// The `viewer_auth` cookie of a login answer, read from its `Set-Cookie` headers.
    static func sessionCookie(in response: HTTPURLResponse) -> HTTPCookie? {
        guard let url = response.url else { return nil }
        var fields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            if let key = key as? String, let value = value as? String { fields[key] = value }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            .first { $0.name == cookieName && !$0.value.isEmpty }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(APIError) -> T {
        do {
            return try ArchiveDecoder.decode(type, from: data)
        } catch {
            // The description holds the coding path only, never message text or names.
            Self.log.debug("decoding failure \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func send(_ request: URLRequest, endpoint: Endpoint) async throws(APIError) -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            let mapped = APIError.from(transport: error)
            if !mapped.isCancellation {
                Self.log.debug("transport failure \(String(describing: mapped), privacy: .public)")
            }
            throw mapped
        }
        guard let http = response as? HTTPURLResponse else { throw .transport(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.from(status: http.statusCode, body: data)
        }
        return (data, http)
    }
}
