import Foundation

/// A chat's display title: `title`, else first and last name, else `@username`, else "Deleted account".
enum ChatTitle {
    static func make(title: String?, firstName: String?, lastName: String?, username: String?) -> String {
        if let title = title?.nonBlank { return title }
        let name = [firstName?.nonBlank, lastName?.nonBlank].compactMap(\.self).joined(separator: " ")
        if !name.isEmpty { return name }
        if let username = username?.nonBlank { return "@\(username)" }
        return String(localized: "chat.deletedAccount")
    }
}

extension Chat {
    var displayTitle: String {
        ChatTitle.make(title: title, firstName: firstName, lastName: lastName, username: username)
    }
}

/// The second line of a chat row, built from the row's `preview` alone; the app never fetches a message
/// to build it.
struct PreviewLine: Equatable, Sendable {
    /// "You" or a first name, shown before the text. Nil for channels, the other side of a private chat
    /// and service rows.
    let sender: String?
    /// An SF Symbol for media kinds, polls and service rows.
    let symbol: String?
    /// The message text, or a label for the kind when there is none. Empty only for a service row whose
    /// action this version cannot word, which shows its glyph alone, as in the thread.
    let text: String
    /// Service rows read as a sentence, without a sender, in the secondary style.
    let isService: Bool

    init(sender: String?, symbol: String?, text: String, isService: Bool = false) {
        self.sender = sender
        self.symbol = symbol
        self.text = text
        self.isService = isService
    }

    init?(_ preview: ChatPreview?) {
        guard let preview else { return nil }
        let kind = preview.kind ?? "message"
        let text = preview.text?.nonBlank
        if kind == "service" {
            let sentence = text ?? ServiceText.sentence(action: preview.action, title: preview.actionTitle,
                                                        actor: preview.sender?.nonBlank)
            self.init(sender: nil, symbol: ServiceText.symbol, text: sentence ?? "", isService: true)
            return
        }
        let sender: String? = switch preview.sender?.nonBlank {
        case "You" where preview.outgoing: String(localized: "preview.you")
        case let name: name
        }
        let label = MediaKindLabel(kind: kind)
        self.init(sender: sender, symbol: label?.symbol, text: text ?? label?.title ?? String(localized: "preview.kind.message"))
    }
}

/// The label and glyph of a message kind with no text of its own: "Photo", "Voice message", "Location"...
struct MediaKindLabel: Equatable, Sendable {
    let symbol: String
    let title: String

    /// Nil for `text` and `message`, which carry no glyph, and for a kind this version does not know.
    init?(kind: String) {
        let pair: (String, String.LocalizationValue)? = switch kind {
        case "photo": ("photo", "preview.kind.photo")
        case "video": ("video", "preview.kind.video")
        case "video_note": ("video.circle", "preview.kind.videoNote")
        case "voice": ("mic", "preview.kind.voice")
        case "audio": ("music.note", "preview.kind.audio")
        case "animation": ("play.square", "preview.kind.animation")
        case "sticker": ("face.smiling", "preview.kind.sticker")
        case "document": ("doc", "preview.kind.document")
        case "geo": ("mappin.and.ellipse", "preview.kind.location")
        case "geo_live": ("location", "preview.kind.liveLocation")
        case "venue": ("mappin.and.ellipse", "preview.kind.venue")
        case "contact": ("person.crop.circle", "preview.kind.contact")
        case "poll": ("chart.bar", "preview.kind.poll")
        case "dice": ("dice", "preview.kind.dice")
        case "game": ("gamecontroller", "preview.kind.game")
        case "invoice": ("creditcard", "preview.kind.invoice")
        case "story": ("circle.dashed", "preview.kind.story")
        case "giveaway", "giveaway_results": ("gift", "preview.kind.giveaway")
        case "webpage": ("link", "preview.kind.link")
        case "unsupported": ("questionmark.square", "preview.kind.unsupported")
        default: nil
        }
        guard let pair else { return nil }
        symbol = pair.0
        title = String(localized: pair.1)
    }
}

/// The server's wording of a service row whose sentence the archive did not store, from its `action_type`
/// and `new_title`. The chat list preview and the thread use the same table.
enum ServiceText {
    static let symbol = "info.circle"

    /// The sentence, prefixed with `actor` when known, or nil for an action this version cannot word.
    static func sentence(action: String?, title: String?, actor: String?) -> String? {
        let title = title?.nonBlank
        switch (action, actor, title) {
        case let ("chat_joined_by_link", actor?, _):
            return String(localized: "service.joinedByLink.actor \(actor)")
        case ("chat_joined_by_link", nil, _):
            return String(localized: "service.joinedByLink")
        case let ("chat_joined_by_request", actor?, _):
            return String(localized: "service.joinedByRequest.actor \(actor)")
        case ("chat_joined_by_request", nil, _):
            return String(localized: "service.joinedByRequest")
        case let ("chat_edit_photo", actor?, _):
            return String(localized: "service.editPhoto.actor \(actor)")
        case ("chat_edit_photo", nil, _):
            return String(localized: "service.editPhoto")
        case let ("chat_delete_photo", actor?, _):
            return String(localized: "service.deletePhoto.actor \(actor)")
        case ("chat_delete_photo", nil, _):
            return String(localized: "service.deletePhoto")
        case let ("chat_edit_title", actor?, title?):
            return String(localized: "service.editTitle.actor \(actor) \(title)")
        case let ("chat_edit_title", nil, title?):
            return String(localized: "service.editTitle \(title)")
        case let ("chat_edit_title", actor?, nil):
            return String(localized: "service.editTitleUnknown.actor \(actor)")
        case ("chat_edit_title", nil, nil):
            return String(localized: "service.editTitleUnknown")
        case let ("chat_create", actor?, title?):
            return String(localized: "service.chatCreate.actor \(actor) \(title)")
        case let ("chat_create", nil, title?):
            return String(localized: "service.chatCreate \(title)")
        case let ("chat_create", actor?, nil):
            return String(localized: "service.chatCreateUnknown.actor \(actor)")
        case ("chat_create", nil, nil):
            return String(localized: "service.chatCreateUnknown")
        case let ("channel_create", actor?, title?):
            return String(localized: "service.channelCreate.actor \(actor) \(title)")
        case let ("channel_create", nil, title?):
            return String(localized: "service.channelCreate \(title)")
        case let ("channel_create", actor?, nil):
            return String(localized: "service.channelCreateUnknown.actor \(actor)")
        case ("channel_create", nil, nil):
            return String(localized: "service.channelCreateUnknown")
        case ("chat_add_user", _, _):
            return String(localized: "service.addUser")
        case ("chat_delete_user", _, _):
            return String(localized: "service.deleteUser")
        default:
            return nil
        }
    }
}

extension String {
    /// The text without surrounding whitespace, or nil when nothing is left.
    var nonBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
