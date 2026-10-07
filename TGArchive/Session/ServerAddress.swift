import Foundation

/// The address of one archive server: scheme, host, optional port and optional path prefix, with no trailing
/// slash. The app builds every URL under it, so a server behind a reverse proxy at `/archive` works.
struct ServerAddress: Hashable, Sendable, Codable {
    let baseURL: URL

    /// What `parse` found in the text the user typed or pasted.
    struct Parsed: Hashable, Sendable {
        let address: ServerAddress
        /// The token of a pasted share link (`.../#token=VALUE`), exactly as written.
        let token: String?
    }

    /// The host as shown to the user ("where the password goes").
    var host: String { baseURL.host(percentEncoded: false) ?? baseURL.absoluteString }

    var isHTTPS: Bool { baseURL.scheme == "https" }

    /// Accepts `host`, `host:8000`, `http(s)://host[:port][/prefix]` and a share link
    /// `https://host[/prefix]/#token=VALUE`. The scheme defaults to https. Returns nil for anything else.
    /// The token is never checked for format: the server only needs a non-empty string.
    static func parse(_ text: String) -> Parsed? {
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rest.isEmpty, !rest.contains(where: \.isWhitespace) else { return nil }

        var token: String?
        if let hash = rest.firstIndex(of: "#") {
            let fragment = rest[rest.index(after: hash)...]
            for pair in fragment.split(separator: "&") where pair.hasPrefix("token=") {
                let value = pair.dropFirst("token=".count)
                if !value.isEmpty { token = String(value) }
            }
            rest = String(rest[..<hash])
        }

        let lowered = rest.lowercased()
        if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") {
            // Kept as typed; the scheme is lowercased below.
        } else if rest.contains("://") {
            return nil
        } else {
            rest = "https://" + rest
        }

        guard var components = URLComponents(string: rest),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        components.scheme = scheme
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path
        guard let url = components.url else { return nil }
        return Parsed(address: ServerAddress(baseURL: url), token: token)
    }

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let parsed = ServerAddress.parse(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a server address")
        }
        self = parsed.address
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(baseURL.absoluteString)
    }
}
