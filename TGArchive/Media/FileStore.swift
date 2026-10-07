import Foundation

/// Original files downloaded for Quick Look, under `tmp/Media/<ref>/<key>/<file name>`. Derived data: the
/// sign-out wipe deletes all of it.
struct FileStore: Sendable {
    static let shared = FileStore(root: URL.temporaryDirectory.appending(path: "Media", directoryHint: .isDirectory))

    let root: URL

    /// Where a file lands. Every part is reduced to a plain file name, so nothing a server sends can point
    /// outside `root`.
    func destination(ref: String, key: String, fileName: String?) -> URL {
        let name = Self.safeName(fileName) ?? Self.safeName(key) ?? "file"
        return root
            .appending(path: Self.safeName(ref) ?? "chat", directoryHint: .isDirectory)
            .appending(path: Self.safeName(key) ?? "media", directoryHint: .isDirectory)
            .appending(path: name, directoryHint: .notDirectory)
    }

    /// Downloads `/media/{ref}/{key}` with the session cookie. The request goes through the session's HTTP
    /// cache, which revalidates any stored copy, so the server checks access on every open.
    func download(ref: String, key: String, fileName: String?, client: APIClient) async throws(MediaFailure) -> URL {
        let request = client.request(for: .media(ref: ref, key: key))
        let temporary: URL
        let response: URLResponse
        do {
            (temporary, response) = try await client.urlSession.download(for: request)
        } catch {
            throw .failed(APIError.from(transport: error))
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse else { throw .failed(.transport(.badServerResponse)) }
        guard (200..<300).contains(http.statusCode) else {
            let body = (try? Data(contentsOf: temporary)) ?? Data()
            throw MediaFailure(APIError.from(status: http.statusCode, body: body))
        }
        let target = destination(ref: ref, key: key, fileName: fileName)
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: target.path(percentEncoded: false)) {
                try manager.removeItem(at: target)
            }
            try manager.moveItem(at: temporary, to: target)
        } catch {
            throw .failed(.transport(.cannotWriteToFile))
        }
        return target
    }

    /// Deletes every downloaded file.
    func wipe() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The last path component with separators and leading dots removed, or nil when nothing is left.
    static func safeName(_ text: String?) -> String? {
        guard let text else { return nil }
        let last = text.split(separator: "/").last.map(String.init) ?? text
        var cleaned = last.replacingOccurrences(of: ":", with: "_")
            .filter { !$0.isNewline && $0 != "\0" && $0 != "\\" }
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? nil : String(cleaned.prefix(200))
    }
}
