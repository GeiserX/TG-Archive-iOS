import Foundation

/// The invented archive behind "Try the demo": the demo server's chats, messages and photos, bundled in the
/// app (`scripts/build-demo-archive.sh`) and answered in place of a server by `DemoURLProtocol`. The rest of
/// the app runs unchanged on an ordinary `APIClient`, and nothing in demo mode reaches the network.
///
/// Immutable after `init`, so any thread may ask it.
final class DemoArchive: @unchecked Sendable {
    /// `.invalid` never resolves (RFC 2606): a request that got past the protocol would fail, not leave.
    static let address = ServerAddress(baseURL: URL(string: "https://demo.tgarchive.invalid")!)
    static let shared = DemoArchive(bundle: .main)

    struct Response: Sendable {
        let status: Int
        let contentType: String
        let body: Data
    }

    private let bundle: Bundle
    private let authCheck: [String: Any]
    private let stats: [String: Any]
    private let folders: [[String: Any]]
    private let folderMembers: [String: [String]]
    private let chats: [[String: Any]]
    private let archived: [[String: Any]]
    private let topics: [String: [[String: Any]]]
    /// Per chat ref, newest first by date, then id.
    private let messages: [String: [[String: Any]]]

    init(bundle: Bundle) {
        self.bundle = bundle
        let root = bundle.url(forResource: "DemoArchive", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        authCheck = root["auth_check"] as? [String: Any] ?? [:]
        stats = root["stats"] as? [String: Any] ?? [:]
        folders = root["folders"] as? [[String: Any]] ?? []
        folderMembers = root["folder_members"] as? [String: [String]] ?? [:]
        chats = root["chats"] as? [[String: Any]] ?? []
        archived = root["archived"] as? [[String: Any]] ?? []
        topics = root["topics"] as? [String: [[String: Any]]] ?? [:]
        messages = root["messages"] as? [String: [[String: Any]]] ?? [:]
    }

    /// A client whose every request is answered from this archive, with its own memory-only cache.
    static func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemoURLProtocol.self]
        return APIClient(server: address, cookie: nil, configuration: configuration,
                         cache: URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 0, directory: nil))
    }

    func respond(to request: URLRequest) -> Response {
        guard let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return notFound
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let path = components.path.split(separator: "/").map(String.init)
        return respond(method: request.httpMethod ?? "GET", path: path, query: query)
    }

    func respond(method: String, path: [String], query: [String: String]) -> Response {
        switch (method, path.joined(separator: "/")) {
        case ("GET", "api/health"): return json(["status": "ok"])
        case ("GET", "api/auth/check"): return json(authCheck)
        case ("POST", "api/logout"): return json(["message": "Logged out"])
        case ("GET", "api/stats"): return json(stats)
        case ("GET", "api/folders"): return json(["folders": folders])
        case ("GET", "api/archived/count"): return json(["count": archived.count])
        case ("GET", "api/chats"): return chatList(query)
        case ("GET", "api/search/messages"): return search(query)
        default: break
        }
        guard method == "GET" else { return notFound }
        if path.count >= 3, path[0] == "api", path[1] == "chats" {
            let ref = path[2]
            guard let chat = chat(ref) else { return notFound }
            switch Array(path.dropFirst(3)) {
            case []: return json(chat)
            case ["topics"]: return json(["topics": topics[ref] ?? []])
            case ["messages"]: return messagePage(ref, query)
            default: return notFound
            }
        }
        if path.first == "media" {
            if path.count == 5, path[1] == "thumb" { return photo(path[3], path[4]) }
            if path.count == 3, path[1] != "avatar" { return photo(path[1], path[2]) }
        }
        return notFound
    }

    // MARK: - Routes

    private func chatList(_ query: [String: String]) -> Response {
        var list = query["archived"] == "true" ? archived : chats
        if let folder = query["folder_id"] {
            let members = Set(folderMembers[folder] ?? [])
            list = list.filter { members.contains($0["ref"] as? String ?? "") }
        }
        if let search = query["search"], !search.isEmpty {
            list = list.filter { Self.displayName($0).localizedStandardContains(search) }
        }
        let limit = Self.number(query["limit"], default: 50, in: 1...200)
        let offset = Self.number(query["offset"], default: 0, in: 0...Int.max)
        let page = Array(list.dropFirst(offset).prefix(limit))
        return json(["chats": page, "total": list.count, "limit": limit, "offset": offset,
                     "has_more": offset + page.count < list.count])
    }

    /// The server's cursors: `after_id` takes the nearest newer ids, `before_date` with `before_id` walks
    /// back by date then id, a lone `before_id` walks back by id. Every page is newest first.
    private func messagePage(_ ref: String, _ query: [String: String]) -> Response {
        var list = messages[ref] ?? []
        if let topic = query["topic_id"].flatMap(Int.init) {
            list = list.filter { $0["reply_to_top_id"] as? Int == topic }
        }
        let limit = Self.number(query["limit"], default: 50, in: 1...500)
        let beforeID = query["before_id"].flatMap(Int.init)
        let page: [[String: Any]]
        if let after = query["after_id"].flatMap(Int.init) {
            page = Array(list.filter { Self.id($0) > after }.sorted { Self.id($0) < Self.id($1) }.prefix(limit).reversed())
        } else if let beforeDate = query["before_date"].flatMap(ArchiveDate.parse) {
            page = Array(list.filter { message in
                let date = Self.date(message)
                if date < beforeDate { return true }
                guard let beforeID else { return false }
                return date == beforeDate && Self.id(message) < beforeID
            }.prefix(limit))
        } else if let beforeID {
            page = Array(list.filter { Self.id($0) < beforeID }.sorted { Self.id($0) > Self.id($1) }.prefix(limit))
        } else {
            page = Array(list.prefix(limit))
        }
        return json(page)
    }

    private func search(_ query: [String: String]) -> Response {
        let text = query["q"] ?? ""
        let limit = Self.number(query["limit"], default: 20, in: 1...100)
        let offset = Self.number(query["offset"], default: 0, in: 0...Int.max)
        var hits: [(message: [String: Any], chat: [String: Any])] = []
        if !text.isEmpty {
            for chat in chats + archived {
                let ref = chat["ref"] as? String ?? ""
                for message in messages[ref] ?? [] where (message["text"] as? String)?.localizedStandardContains(text) == true {
                    hits.append((message, chat))
                }
            }
        }
        hits.sort { (Self.date($0.message), Self.id($0.message)) > (Self.date($1.message), Self.id($1.message)) }
        let page = hits.dropFirst(offset).prefix(limit).map { hit -> [String: Any] in
            let chat = hit.chat
            let ref = chat["ref"] as? String ?? ""
            let topic = (hit.message["reply_to_top_id"] as? Int).flatMap { id in
                topics[ref]?.first { $0["id"] as? Int == id }?["title"]
            }
            return [
                "id": Self.id(hit.message),
                "date": hit.message["date"] ?? NSNull(),
                "text": hit.message["text"] ?? NSNull(),
                "sender_name": hit.message["sender_name"] ?? NSNull(),
                "is_deleted": hit.message["is_deleted"] ?? 0,
                "topic_title": topic ?? NSNull(),
                "matched_in": "message",
                "chat": [
                    "ref": ref,
                    "title": chat["title"] ?? NSNull(),
                    "first_name": chat["first_name"] ?? NSNull(),
                    "last_name": chat["last_name"] ?? NSNull(),
                    "username": chat["username"] ?? NSNull(),
                    "type": chat["type"] ?? NSNull(),
                    "is_forum": (chat["is_forum"] as? Int ?? 0) != 0,
                    "avatar_url": NSNull(),
                ],
            ]
        }
        return json(["query": text, "limit": limit, "offset": offset, "indexed": true,
                     "has_more": offset + page.count < hits.count, "results": page])
    }

    /// The bundled photos; everything else (videos, voice notes, documents, stickers, avatars) is missing,
    /// which the app shows with its own tiles.
    private func photo(_ ref: String, _ key: String) -> Response {
        guard let url = bundle.url(forResource: "demo-\(ref)-\(key)", withExtension: "jpg"),
              let data = try? Data(contentsOf: url)
        else { return notFound }
        return Response(status: 200, contentType: "image/jpeg", body: data)
    }

    // MARK: - Helpers

    private func chat(_ ref: String) -> [String: Any]? {
        (chats + archived).first { $0["ref"] as? String == ref }
    }

    private var notFound: Response { json(["detail": "Not Found"], status: 404) }

    private func json(_ value: Any, status: Int = 200) -> Response {
        let body = (try? JSONSerialization.data(withJSONObject: value)) ?? Data("{}".utf8)
        return Response(status: status, contentType: "application/json", body: body)
    }

    private static func id(_ message: [String: Any]) -> Int { message["id"] as? Int ?? 0 }

    private static func date(_ message: [String: Any]) -> Date {
        (message["date"] as? String).flatMap(ArchiveDate.parse) ?? .distantPast
    }

    private static func number(_ text: String?, default value: Int, in range: ClosedRange<Int>) -> Int {
        min(max(text.flatMap(Int.init) ?? value, range.lowerBound), range.upperBound)
    }

    private static func displayName(_ chat: [String: Any]) -> String {
        if let title = chat["title"] as? String, !title.isEmpty { return title }
        return [chat["first_name"], chat["last_name"]].compactMap { $0 as? String }.joined(separator: " ")
    }
}

extension Session {
    /// The bundled demo archive, not a server.
    var isDemo: Bool { stored.server == DemoArchive.address }
}

/// Answers every request to the demo address from `DemoArchive.shared`, without a network.
final class DemoURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host() == DemoArchive.address.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = DemoArchive.shared.respond(to: request)
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": response.contentType])!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
