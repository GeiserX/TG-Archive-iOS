import Foundation

/// One message of `GET /api/chats/{ref}/messages` (a bare JSON array, newest first) and of the pinned list.
/// Every field except `id` and `date` is optional, and the parts the thread can live without decode
/// leniently, so one odd message never fails its page.
struct Message: Decodable, Hashable, Sendable, Identifiable {
    let id: Int
    let date: Date
    let text: String?
    let senderID: Int?
    let senderName: String?
    let firstName: String?
    let lastName: String?
    @FlexBool var isOutgoing: Bool
    /// Deleted in Telegram; the archive kept it.
    @FlexBool var isDeleted: Bool
    @FlexBool var isPinned: Bool
    let deletedAt: Date?
    let editDate: Date?
    /// Telegram's flag for `edit_date`: 1 when the edit is not to be shown (only reactions changed).
    let editHide: Int?
    /// Earlier versions the archive kept.
    let versionCount: Int?
    let replyToMsgID: Int?
    /// The forum topic a message belongs to.
    let replyToTopID: Int?
    let replyToText: String?
    let replyToSenderName: String?
    let replyToMediaType: String?
    @Lenient var media: MessageMedia?
    @Lenient var reactions: [Reaction]?
    @Lenient var removedReactions: [RemovedReaction]?
    @Lenient var snapshots: Snapshots?
    @Lenient var rawData: RawData?
    /// Root-absolute path from the server; the app builds it through `Endpoint.senderAvatar(ref:messageID:)`.
    let senderAvatarURL: String?

    /// The server's own pencil rule: Telegram marks the edit as shown, or the archive kept an earlier version.
    var isEdited: Bool {
        (editDate != nil && editHide != 1) || (versionCount ?? 0) > 0
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, text
        case senderID = "senderId"
        case senderName, firstName, lastName, isOutgoing, isDeleted, isPinned, deletedAt, editDate, editHide
        case versionCount
        case replyToMsgID = "replyToMsgId"
        case replyToTopID = "replyToTopId"
        case replyToText, replyToSenderName, replyToMediaType, media, reactions, removedReactions, snapshots
        case rawData
        case senderAvatarURL = "senderAvatarUrl"
    }
}

/// A page of `GET /api/chats/{ref}/messages`, newest first. A message that does not decode is dropped and
/// counted instead of failing the page.
struct MessagePage: Decodable, Hashable, Sendable {
    let messages: [Message]
    let dropped: Int

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var messages: [Message] = []
        var dropped = 0
        while !container.isAtEnd {
            if let message = try? container.decode(Message.self) {
                messages.append(message)
            } else {
                // A failed decode does not advance the container; step over the element.
                _ = try container.decode(Skipped.self)
                dropped += 1
            }
        }
        self.messages = messages
        self.dropped = dropped
    }

    private struct Skipped: Decodable {}
}

/// The archive's media kinds. Anything this version does not know is `.unsupported`.
enum MediaType: String, Decodable, Hashable, Sendable {
    case photo, video, voice, audio, animation, sticker, document, geo, venue, contact, poll, dice, game, invoice
    case story, giveaway, webpage
    case videoNote = "video_note"
    case geoLive = "geo_live"
    case giveawayResults = "giveaway_results"
    case unsupported

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MediaType(rawValue: raw) ?? .unsupported
    }
}

/// A message's media row. `id` is the media key, `{message_id}_{type}`, used in every media URL.
struct MessageMedia: Decodable, Hashable, Sendable, Identifiable {
    let id: String
    let type: MediaType
    /// Nil when there is no file to fetch: a kind without one, not downloaded, or downloads off for this login.
    let url: String?
    let fileName: String?
    let fileSize: Int?
    let mimeType: String?
    let width: Int?
    let height: Int?
    /// Seconds.
    let duration: Double?
    @FlexBool var downloaded: Bool
    /// `oversize`, `filtered`, `map_not_served`, or nil.
    let skipReason: String?
    let noDownload: Bool?
    @Lenient var transcripts: [Transcript]?

    /// The key the media routes take.
    var key: String { id }
}

struct Transcript: Decodable, Hashable, Sendable {
    /// `done`, `pending`, `failed` and the like; only `done` has text to show.
    let status: String?
    let text: String?
    let language: String?
}

/// A live reaction: one entry per emoji with its count. A custom emoji reads `custom_<id>`.
struct Reaction: Decodable, Hashable, Sendable {
    let emoji: String
    let count: Int
}

/// A reaction taken back that the archive kept, from its latest drop.
struct RemovedReaction: Decodable, Hashable, Sendable {
    let emoji: String
    let count: Int
    let countBefore: Int?
    let removedAt: Date?
    let backAt: Date?
}

/// The newest state the archive kept of a message's poll.
struct Snapshots: Decodable, Hashable, Sendable {
    @Lenient var poll: Snapshot<Poll>?
}

struct Snapshot<Payload: Decodable & Hashable & Sendable>: Decodable, Hashable, Sendable {
    /// The whole newest state; a poll update that carried only results holds only `results`.
    let payload: Payload?
    let observedAt: Date?
    let source: String?
    let count: Int?
    let differsFromFirst: Bool?
}

/// The parts of the stored Telegram message the thread renders.
struct RawData: Decodable, Hashable, Sendable {
    @Lenient var entities: [Entity]?
    let forwardFromName: String?
    /// Album id; the archive sends a number or a string.
    let groupedID: String?
    @Lenient var geo: GeoPoint?
    @Lenient var venue: Venue?
    @Lenient var geoLive: LiveLocation?
    @Lenient var contact: Contact?
    @Lenient var poll: Poll?
    let serviceType: String?
    /// For a service row: `chat_joined_by_link`, `chat_edit_title`, ...
    let actionType: String?
    let newTitle: String?
    @Lenient var sticker: Sticker?

    private enum CodingKeys: String, CodingKey {
        case entities, forwardFromName
        case groupedID = "groupedId"
        case geo, venue, geoLive, contact, poll, serviceType, actionType, newTitle, sticker
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _entities = try container.decode(Lenient<[Entity]>.self, forKey: .entities)
        forwardFromName = try? container.decodeIfPresent(String.self, forKey: .forwardFromName)
        groupedID = (try? container.decodeIfPresent(NumberOrString.self, forKey: .groupedID))?.value
        _geo = try container.decode(Lenient<GeoPoint>.self, forKey: .geo)
        _venue = try container.decode(Lenient<Venue>.self, forKey: .venue)
        _geoLive = try container.decode(Lenient<LiveLocation>.self, forKey: .geoLive)
        _contact = try container.decode(Lenient<Contact>.self, forKey: .contact)
        _poll = try container.decode(Lenient<Poll>.self, forKey: .poll)
        serviceType = try? container.decodeIfPresent(String.self, forKey: .serviceType)
        actionType = try? container.decodeIfPresent(String.self, forKey: .actionType)
        newTitle = try? container.decodeIfPresent(String.self, forKey: .newTitle)
        _sticker = try container.decode(Lenient<Sticker>.self, forKey: .sticker)
    }
}

/// A formatting run: `bold`, `italic`, `text_url`, `custom_emoji`, ... over UTF-16 `offset` and `length`.
struct Entity: Decodable, Hashable, Sendable {
    let type: String
    let offset: Int
    let length: Int
    /// For `text_url`.
    let url: String?
    /// For `pre`.
    let language: String?
    /// For `custom_emoji`, as a string.
    let documentID: String?

    private enum CodingKeys: String, CodingKey {
        case type, offset, length, url, language
        case documentID = "documentId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        offset = try container.decode(Int.self, forKey: .offset)
        length = try container.decode(Int.self, forKey: .length)
        url = try? container.decodeIfPresent(String.self, forKey: .url)
        language = try? container.decodeIfPresent(String.self, forKey: .language)
        documentID = (try? container.decodeIfPresent(NumberOrString.self, forKey: .documentID))?.value
    }
}

/// A point. Telegram can send a location without one, so both coordinates are optional.
struct GeoPoint: Decodable, Hashable, Sendable {
    let lat: Double?
    let long: Double?
    let accuracyRadius: Int?
}

struct Venue: Decodable, Hashable, Sendable {
    let title: String?
    let address: String?
    let lat: Double?
    let long: Double?
}

struct LiveLocation: Decodable, Hashable, Sendable {
    let lat: Double?
    let long: Double?
    /// Seconds the live location was shared for.
    let period: Int?
    let heading: Int?
    /// When this position was current.
    let at: Date?
}

struct Contact: Decodable, Hashable, Sendable {
    let firstName: String?
    let lastName: String?
    let phoneNumber: String?
}

/// A poll as first captured, or a snapshot of a later state; every field optional so a snapshot can override
/// the first capture field by field.
struct Poll: Decodable, Hashable, Sendable {
    let question: String?
    let answers: [PollAnswer]?
    let closed: Bool?
    let multipleChoice: Bool?
    let quiz: Bool?
    let results: PollResults?
}

struct PollAnswer: Decodable, Hashable, Sendable {
    let text: String?
    /// Base64 option id, matched against `PollResults.results[].option`.
    let option: String?
}

struct PollResults: Decodable, Hashable, Sendable {
    let totalVoters: Int?
    let results: [PollOptionResult]?
}

struct PollOptionResult: Decodable, Hashable, Sendable {
    let option: String?
    let voters: Int?
    let correct: Bool?
}

/// A sticker's alternative emoji, shown for the animated kinds v1 does not play.
struct Sticker: Decodable, Hashable, Sendable {
    let emoji: String?
}
