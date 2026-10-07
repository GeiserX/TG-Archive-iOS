import Foundation

/// Where a page of messages starts.
enum MessageCursor: Hashable, Sendable {
    /// The newest page.
    case newest
    /// Older than the message with this date and id: the date-and-id cursor for scrolling up.
    case before(date: Date, id: Int)
    /// Ids below this one: the anchor page of a search hit uses `anchor + 1`.
    case beforeID(Int)
    /// Ids above this one: the pages newer than an anchor.
    case after(id: Int)
}

/// The two thumbnail widths the server makes.
enum ThumbnailSize: Int, Hashable, Sendable {
    case small = 200
    case large = 400
}

/// One case per server route the app calls. `request(base:)` builds the URL under the server's path prefix;
/// the app never uses the root-absolute `avatar_url` or `media.url` strings from the server.
enum Endpoint: Hashable, Sendable {
    case health
    case authCheck
    case login
    case tokenLogin
    case logout
    case chats(limit: Int = 50, offset: Int = 0, search: String? = nil, archived: Bool? = false, folderID: Int? = nil)
    case chat(ref: String)
    case folders
    case archivedCount
    case topics(ref: String)
    case messages(ref: String, limit: Int = 50, cursor: MessageCursor = .newest, topicID: Int? = nil)
    case search(query: String, limit: Int = 20, offset: Int = 0)
    case stats
    case media(ref: String, key: String)
    case thumbnail(size: ThumbnailSize, ref: String, key: String)
    case avatar(ref: String)
    case senderAvatar(ref: String, messageID: Int)

    var method: String {
        switch self {
        case .login, .tokenLogin, .logout: "POST"
        default: "GET"
        }
    }

    /// Media bytes go through the HTTP cache and are revalidated with `If-None-Match` on every reuse.
    /// JSON is never served from the cache.
    var isMedia: Bool {
        switch self {
        case .media, .thumbnail, .avatar, .senderAvatar: true
        default: false
        }
    }

    /// The sign-out call must not hold up the local wipe for long.
    var timeout: TimeInterval {
        self == .logout ? 5 : 30
    }

    private var pathSegments: [String] {
        switch self {
        case .health: ["api", "health"]
        case .authCheck: ["api", "auth", "check"]
        case .login: ["api", "login"]
        case .tokenLogin: ["auth", "token"]
        case .logout: ["api", "logout"]
        case .chats: ["api", "chats"]
        case let .chat(ref): ["api", "chats", ref]
        case .folders: ["api", "folders"]
        case .archivedCount: ["api", "archived", "count"]
        case let .topics(ref): ["api", "chats", ref, "topics"]
        case let .messages(ref, _, _, _): ["api", "chats", ref, "messages"]
        case .search: ["api", "search", "messages"]
        case .stats: ["api", "stats"]
        case let .media(ref, key): ["media", ref, key]
        case let .thumbnail(size, ref, key): ["media", "thumb", String(size.rawValue), ref, key]
        case let .avatar(ref): ["media", "avatar", ref]
        case let .senderAvatar(ref, messageID): ["media", "avatar", ref, String(messageID)]
        }
    }

    private var queryItems: [URLQueryItem] {
        switch self {
        case let .chats(limit, offset, search, archived, folderID):
            var items = [URLQueryItem(name: "limit", value: String(limit)),
                         URLQueryItem(name: "offset", value: String(offset))]
            if let search, !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
            if let archived { items.append(URLQueryItem(name: "archived", value: archived ? "true" : "false")) }
            if let folderID { items.append(URLQueryItem(name: "folder_id", value: String(folderID))) }
            return items
        case let .messages(_, limit, cursor, topicID):
            var items = [URLQueryItem(name: "limit", value: String(limit))]
            switch cursor {
            case .newest:
                break
            case let .before(date, id):
                items.append(URLQueryItem(name: "before_date", value: ArchiveDate.format(date)))
                items.append(URLQueryItem(name: "before_id", value: String(id)))
            case let .beforeID(id):
                items.append(URLQueryItem(name: "before_id", value: String(id)))
            case let .after(id):
                items.append(URLQueryItem(name: "after_id", value: String(id)))
            }
            if let topicID { items.append(URLQueryItem(name: "topic_id", value: String(topicID))) }
            return items
        case let .search(query, limit, offset):
            return [URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "limit", value: String(limit)),
                    URLQueryItem(name: "offset", value: String(offset))]
        default:
            return []
        }
    }

    /// The URL under `base` (scheme, host, port and path prefix), every path segment percent-encoded.
    func url(base: URL) -> URL {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        for segment in pathSegments {
            path += "/" + (segment.addingPercentEncoding(withAllowedCharacters: Self.segmentAllowed) ?? segment)
        }
        components.percentEncodedPath = path
        let items = queryItems
        if items.isEmpty {
            components.query = nil
        } else {
            components.queryItems = items
            // URLComponents leaves "+" as is, and the server reads a bare "+" in a query as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        components.fragment = nil
        return components.url ?? base
    }

    func request(base: URL) -> URLRequest {
        var request = URLRequest(url: url(base: base), timeoutInterval: timeout)
        request.httpMethod = method
        request.cachePolicy = isMedia ? .useProtocolCachePolicy : .reloadIgnoringLocalCacheData
        if !isMedia { request.setValue("application/json", forHTTPHeaderField: "Accept") }
        return request
    }

    private static let segmentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/;?#")
        return set
    }()
}
