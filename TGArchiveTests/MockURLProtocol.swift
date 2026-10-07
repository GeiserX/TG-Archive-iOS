import Foundation
import Synchronization
@testable import TGArchive

/// A fake archive server for one test. Each one answers under its own host, so tests that run in parallel
/// never see each other's requests. Servers stay registered for the life of the test process.
final class MockServer: Sendable {
    struct Response: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body = Data()
        /// When set, the request fails with this transport error instead of answering.
        var failure: URLError.Code?

        static func json(_ text: String, status: Int = 200, headers: [String: String] = [:]) -> Response {
            Response(status: status, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a },
                     body: Data(text.utf8))
        }

        static func fixture(_ name: String, status: Int = 200, headers: [String: String] = [:]) throws -> Response {
            Response(status: status, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a },
                     body: try Fixture.data(name))
        }

        static func transportFailure(_ code: URLError.Code) -> Response {
            Response(failure: code)
        }
    }

    /// A request as the server saw it, body included.
    struct Recorded: Sendable {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data?

        var cookie: String? { headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value }
    }

    typealias Handler = @Sendable (Recorded) -> Response

    let host: String
    let address: ServerAddress
    private let state: Mutex<(handler: Handler, requests: [Recorded])>

    init(prefix: String = "", handler: @escaping Handler = { _ in Response(status: 404) }) {
        host = "t\(UUID().uuidString.lowercased().prefix(12)).mock.invalid"
        address = ServerAddress.parse("https://\(host)\(prefix)")!.address
        state = Mutex((handler, []))
        MockURLProtocol.register(self)
    }

    func respond(_ handler: @escaping Handler) {
        state.withLock { $0.handler = handler }
    }

    var requests: [Recorded] { state.withLock { $0.requests } }

    func requests(to path: String) -> [Recorded] { requests.filter { $0.path == path } }

    fileprivate func handle(_ recorded: Recorded) -> Response {
        let handler = state.withLock { state in
            state.requests.append(recorded)
            return state.handler
        }
        return handler(recorded)
    }

    /// A session configuration whose requests reach the mock servers.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return configuration
    }

    /// A small in-memory cache, so tests never touch the app's cache directory.
    static func cache() -> URLCache {
        URLCache(memoryCapacity: 1024 * 1024, diskCapacity: 0, directory: nil)
    }
}

/// Routes every request of a mock-configured session to the `MockServer` registered for its host.
final class MockURLProtocol: URLProtocol {
    private static let servers = Mutex<[String: MockServer]>([:])

    static func register(_ server: MockServer) {
        servers.withLock { $0[server.host] = server }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host(),
              let server = Self.servers.withLock({ $0[host] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let recorded = MockServer.Recorded(
            method: request.httpMethod ?? "GET",
            path: components?.percentEncodedPath ?? url.path(),
            query: query,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody ?? request.httpBodyStream.map(Self.read)
        )
        let response = server.handle(recorded)
        if let failure = response.failure {
            client?.urlProtocol(self, didFailWithError: URLError(failure))
            return
        }
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// The committed JSON captured from the demo server.
enum Fixture {
    private final class BundleToken {}

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle(for: BundleToken.self).url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try Data(contentsOf: url)
    }

    static func names() -> [String] {
        (Bundle(for: BundleToken.self).urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }
}
