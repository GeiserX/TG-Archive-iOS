import Foundation

/// What a message shows besides its text, read from its media row and, for the kinds without a file, from
/// `raw_data`. Pure, so the rules are tested without a view.
enum MessageContent: Equatable, Sendable {
    /// Text only, or a link preview (v1 shows the link in the text).
    case none
    case photo(MessageMedia)
    /// A video or an animation (GIF).
    case video(MessageMedia)
    case videoNote(MessageMedia)
    case voice(MessageMedia)
    case audio(MessageMedia)
    case document(MessageMedia)
    case sticker(StickerContent)
    case location(LocationContent)
    /// Nil when the archive kept no details.
    case contact(Contact?)
    /// The newest state the archive kept, or nil when it kept none.
    case poll(Poll?)
    /// A kind this version does not draw: dice, a game, an invoice, a story, a giveaway, or one it does not know.
    case unsupported(MediaType)

    init(_ message: Message) {
        let raw = message.rawData
        if let media = message.media {
            switch media.type {
            case .photo: self = .photo(media)
            case .video, .animation: self = .video(media)
            case .videoNote: self = .videoNote(media)
            case .voice: self = .voice(media)
            case .audio: self = .audio(media)
            case .document: self = .document(media)
            case .sticker: self = .sticker(StickerContent(media: media, emoji: raw?.sticker?.emoji))
            case .geo, .venue, .geoLive:
                self = .location(LocationContent(kind: media.type, raw: raw, media: media))
            case .contact: self = .contact(raw?.contact)
            case .poll: self = .poll(Poll.newest(raw: raw?.poll, snapshot: message.snapshots?.poll?.payload))
            case .webpage: self = .none
            case .dice, .game, .invoice, .story, .giveaway, .giveawayResults, .unsupported:
                self = .unsupported(media.type)
            }
            return
        }
        // The listener writes no media row for the kinds without a file; their content sits in raw_data.
        if raw?.poll != nil || message.snapshots?.poll?.payload != nil {
            self = .poll(Poll.newest(raw: raw?.poll, snapshot: message.snapshots?.poll?.payload))
        } else if raw?.venue != nil {
            self = .location(LocationContent(kind: .venue, raw: raw, media: nil))
        } else if raw?.geoLive != nil {
            self = .location(LocationContent(kind: .geoLive, raw: raw, media: nil))
        } else if raw?.geo != nil {
            self = .location(LocationContent(kind: .geo, raw: raw, media: nil))
        } else if let contact = raw?.contact {
            self = .contact(contact)
        } else {
            self = .none
        }
    }
}

/// Why a file is not fetched. Each case has its own tile, and no request is sent for any of them.
enum MediaUnavailable: Equatable, Sendable {
    /// The login's downloads are off.
    case downloadsOff
    /// Skipped by the archive's size limit.
    case tooLarge
    /// Skipped by the archive's media filter.
    case filtered
    /// The archive has not downloaded it.
    case notDownloaded

    /// Nil when the file can be asked for. Downloads off wins: such a login gets `url` null for everything.
    static func reason(for media: MessageMedia, noDownload: Bool) -> MediaUnavailable? {
        if noDownload || media.noDownload == true { return .downloadsOff }
        if media.url != nil { return nil }
        switch media.skipReason {
        case "oversize": return .tooLarge
        case "filtered": return .filtered
        default: return .notDownloaded
        }
    }

    var titleKey: String.LocalizationValue {
        switch self {
        case .downloadsOff: "media.downloadsOff"
        case .tooLarge: "chat.media.tooLarge"
        case .filtered: "chat.media.filtered"
        case .notDownloaded: "chat.media.notDownloaded"
        }
    }

    var symbol: String {
        switch self {
        case .downloadsOff: "arrow.down.circle.dotted"
        case .tooLarge: "externaldrive.badge.xmark"
        case .filtered: "line.3.horizontal.decrease.circle"
        case .notDownloaded: "icloud.slash"
        }
    }
}

/// A sticker: a static WebP drawn as an image, or an animated one (`.tgs`, `.webm`) shown as its emoji.
struct StickerContent: Equatable, Sendable {
    let media: MessageMedia
    let emoji: String?

    init(media: MessageMedia, emoji: String?) {
        self.media = media
        self.emoji = emoji?.nonBlank
    }

    /// True for a sticker v1 can draw: a WebP or another still image.
    var isStatic: Bool {
        let mime = media.mimeType?.lowercased() ?? ""
        let name = media.fileName?.lowercased() ?? ""
        if mime == "application/x-tgsticker" || mime == "video/webm" || name.hasSuffix(".tgs") || name.hasSuffix(".webm") {
            return false
        }
        return mime.hasPrefix("image/") || name.hasSuffix(".webp") || name.hasSuffix(".png")
    }
}

/// A location, a venue or a live location: the point when Telegram sent one, the venue's name and address,
/// and the map picture the archive kept, when it has one.
struct LocationContent: Equatable, Sendable {
    let kind: MediaType
    let latitude: Double?
    let longitude: Double?
    let title: String?
    let address: String?
    /// The media row whose `url` is the map picture.
    let mapPicture: MessageMedia?

    init(kind: MediaType, raw: RawData?, media: MessageMedia?) {
        self.kind = kind
        let venue = raw?.venue
        switch kind {
        case .venue:
            latitude = venue?.lat ?? raw?.geo?.lat
            longitude = venue?.long ?? raw?.geo?.long
        case .geoLive:
            latitude = raw?.geoLive?.lat ?? raw?.geo?.lat
            longitude = raw?.geoLive?.long ?? raw?.geo?.long
        default:
            latitude = raw?.geo?.lat
            longitude = raw?.geo?.long
        }
        title = kind == .venue ? venue?.title?.nonBlank : nil
        address = kind == .venue ? venue?.address?.nonBlank : nil
        mapPicture = media?.url == nil ? nil : media
    }

    var hasPoint: Bool {
        guard let latitude, let longitude else { return false }
        return (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    /// Apple Maps at the point, labelled with the venue's name when there is one.
    var mapsURL: URL? {
        guard hasPoint, let latitude, let longitude else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        var items = [URLQueryItem(name: "ll", value: "\(latitude),\(longitude)")]
        if let title { items.append(URLQueryItem(name: "q", value: title)) }
        components?.queryItems = items
        return components?.url
    }
}

extension Poll {
    /// The poll as the archive last saw it: the snapshot's fields over the first capture's, field by field,
    /// because a snapshot from a results-only update holds nothing but `results`.
    static func newest(raw: Poll?, snapshot: Poll?) -> Poll? {
        guard let snapshot else { return raw }
        guard let raw else { return snapshot }
        return Poll(question: snapshot.question ?? raw.question,
                    answers: snapshot.answers ?? raw.answers,
                    closed: snapshot.closed ?? raw.closed,
                    multipleChoice: snapshot.multipleChoice ?? raw.multipleChoice,
                    quiz: snapshot.quiz ?? raw.quiz,
                    results: snapshot.results ?? raw.results)
    }

    /// One row per answer with its share of the voters, in the poll's order.
    var rows: [PollRow] {
        let results = self.results?.results ?? []
        let counted = results.compactMap(\.voters).reduce(0, +)
        let total = max(self.results?.totalVoters ?? 0, counted)
        return (answers ?? []).enumerated().map { index, answer in
            let result = results.first { $0.option != nil && $0.option == answer.option }
            let voters = result?.voters
            return PollRow(id: index, text: answer.text ?? "", voters: voters,
                           fraction: total > 0 ? Double(voters ?? 0) / Double(total) : 0,
                           isCorrect: result?.correct == true)
        }
    }
}

struct PollRow: Equatable, Identifiable, Sendable {
    let id: Int
    let text: String
    /// Nil when the archive kept no results for this answer.
    let voters: Int?
    /// From 0 to 1.
    let fraction: Double
    let isCorrect: Bool
}

/// The chips under a bubble: one per live emoji, and the reactions taken back folded into one count.
struct ReactionSummary: Equatable, Sendable {
    struct Chip: Equatable, Identifiable, Sendable {
        /// The emoji, or nil for a custom emoji, which shows a sparkle.
        let emoji: String?
        let count: Int
        let id: String
    }

    let chips: [Chip]
    /// How many reactions were taken back, over every emoji.
    let takenBack: Int

    init(reactions: [Reaction]?, removed: [RemovedReaction]?) {
        chips = (reactions ?? []).filter { $0.count > 0 }.map { reaction in
            Chip(emoji: reaction.emoji.hasPrefix("custom_") ? nil : reaction.emoji, count: reaction.count,
                 id: reaction.emoji)
        }
        takenBack = (removed ?? []).map { max(0, $0.count) }.reduce(0, +)
    }

    var isEmpty: Bool { chips.isEmpty && takenBack == 0 }
}

/// The quoted line above a reply: who wrote the message it answers and its text, or a label for its kind.
struct ReplyQuote: Equatable, Sendable {
    let sender: String?
    let text: String

    /// Nil for a message that answers nothing, and for the forum's topic root, which every message in a
    /// topic points at without quoting it.
    init?(_ message: Message, topicID: Int?) {
        guard let replyID = message.replyToMsgID else { return nil }
        if replyID == topicID || replyID == message.replyToTopID { return nil }
        let sender = message.replyToSenderName?.nonBlank
        let text = message.replyToText?.nonBlank
            ?? message.replyToMediaType.flatMap { MediaKindLabel(kind: $0)?.title }
        guard sender != nil || text != nil else { return nil }
        self.sender = sender
        self.text = text ?? String(localized: "preview.kind.message")
    }
}
