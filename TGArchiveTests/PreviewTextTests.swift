import Foundation
import Testing
@testable import TGArchive

@Suite("Chat preview line")
struct PreviewTextTests {
    private func preview(text: String? = nil, sender: String? = nil, kind: String?, outgoing: Bool = false,
                         action: String? = nil, actionTitle: String? = nil) throws -> ChatPreview {
        var object: [String: Any] = ["message_id": 7, "date": "2026-10-07T13:48:00", "outgoing": outgoing]
        object["text"] = text
        object["sender"] = sender
        object["kind"] = kind
        object["action"] = action
        object["action_title"] = actionTitle
        let data = try JSONSerialization.data(withJSONObject: object)
        return try ArchiveDecoder.decode(ChatPreview.self, from: data)
    }

    @Test("A group message shows its sender and its text, without a glyph")
    func textWithSender() throws {
        let line = try #require(PreviewLine(try preview(text: "Perfect, save me a seat", sender: "Esme", kind: "text")))
        #expect(line == PreviewLine(sender: "Esme", symbol: nil, text: "Perfect, save me a seat"))
    }

    @Test("The account's own message reads as the localized You")
    func outgoing() throws {
        let line = try #require(PreviewLine(try preview(text: "On it now.", sender: "You", kind: "text", outgoing: true)))
        #expect(line.sender == String(localized: "preview.you"))
    }

    @Test("A media kind without text is a glyph and a label")
    func mediaWithoutText() throws {
        let voice = try #require(PreviewLine(try preview(kind: "voice")))
        #expect(voice == PreviewLine(sender: nil, symbol: "mic", text: String(localized: "preview.kind.voice")))
        let place = try #require(PreviewLine(try preview(kind: "geo")))
        #expect(place.symbol == "mappin.and.ellipse")
        #expect(place.text == String(localized: "preview.kind.location"))
    }

    @Test("A captioned video and a poll keep their text and get the kind's glyph")
    func mediaWithText() throws {
        let video = try #require(PreviewLine(try preview(text: "The clip from the ferry", kind: "video")))
        #expect(video == PreviewLine(sender: nil, symbol: "video", text: "The clip from the ferry"))
        let poll = try #require(PreviewLine(try preview(text: "Which book?", sender: "Noor", kind: "poll")))
        #expect(poll == PreviewLine(sender: "Noor", symbol: "chart.bar", text: "Which book?"))
    }

    @Test("Every kind the server documents has a glyph and a label, and text kinds have none")
    func everyKind() {
        let kinds = ["photo", "video", "video_note", "voice", "audio", "animation", "sticker", "document", "geo",
                     "geo_live", "venue", "contact", "poll", "dice", "game", "invoice", "story", "giveaway",
                     "giveaway_results", "webpage", "unsupported"]
        for kind in kinds {
            let label = MediaKindLabel(kind: kind)
            #expect(label != nil, "no label for \(kind)")
            #expect(label?.title.hasPrefix("preview.kind.") == false, "untranslated label for \(kind)")
        }
        #expect(MediaKindLabel(kind: "text") == nil)
        #expect(MediaKindLabel(kind: "message") == nil)
        #expect(MediaKindLabel(kind: "hologram") == nil)
    }

    @Test("A message with neither text nor media, or of an unknown kind, reads as Message")
    func plainMessage() throws {
        let line = try #require(PreviewLine(try preview(kind: "message")))
        #expect(line == PreviewLine(sender: nil, symbol: nil, text: String(localized: "preview.kind.message")))
        let unknown = try #require(PreviewLine(try preview(kind: nil)))
        #expect(unknown.text == String(localized: "preview.kind.message"))
    }

    @Test("A service row with a stored sentence shows it, with no sender")
    func serviceSentence() throws {
        let line = try #require(PreviewLine(try preview(text: "Esme joined the group", kind: "service")))
        #expect(line == PreviewLine(sender: nil, symbol: ServiceText.symbol, text: "Esme joined the group", isService: true))
    }

    @Test("An old service row is worded from action and action_title")
    func serviceAction() throws {
        let renamed = try #require(PreviewLine(try preview(kind: "service", action: "chat_edit_title",
                                                           actionTitle: "Trail crew")))
        #expect(renamed.isService)
        #expect(renamed.text == String(localized: "service.editTitle \("Trail crew")"))
        #expect(renamed.text.contains("Trail crew"))
        let unmapped = try #require(PreviewLine(try preview(kind: "service", action: "chat_migrate_to")))
        #expect(unmapped == PreviewLine(sender: nil, symbol: ServiceText.symbol, text: "", isService: true))
    }

    @Test("No preview, no line")
    func none() {
        #expect(PreviewLine(nil) == nil)
    }

    @Test("Every chat of the demo archive gets a non-empty line")
    func demoArchive() throws {
        let page = try ArchiveDecoder.decode(ChatsPage.self, from: try Fixture.data("chats"))
        for chat in page.chats {
            let line = try #require(PreviewLine(chat.preview), "no preview for \(chat.ref)")
            #expect(!line.text.isEmpty)
        }
        let byTitle = Dictionary(page.chats.map { ($0.displayTitle, PreviewLine($0.preview)) }) { first, _ in first }
        #expect(byTitle["Juniper Vale"]??.symbol == "mic")
        #expect(byTitle["Tobias Fernwood"]??.symbol == "mappin.and.ellipse")
        #expect(byTitle["Kofi Brightwater"]??.sender == String(localized: "preview.you"))
        #expect(byTitle["Harbor Town Weekly"]??.sender == nil)
    }
}

@Suite("Service wording")
struct ServiceTextTableTests {
    @Test("Every action in the server's table is worded, with and without the actor")
    func table() {
        let actions = ["chat_joined_by_link", "chat_joined_by_request", "chat_edit_photo", "chat_delete_photo",
                       "chat_edit_title", "chat_create", "channel_create", "chat_add_user", "chat_delete_user"]
        for action in actions {
            for actor in ["Esme", nil] {
                for title in ["Hikers", nil] {
                    let sentence = ServiceText.sentence(action: action, title: title, actor: actor)
                    #expect(sentence?.isEmpty == false, "\(action) \(actor ?? "-") \(title ?? "-")")
                    #expect(sentence?.hasPrefix("service.") == false, "untranslated \(action)")
                }
            }
        }
        #expect(ServiceText.sentence(action: "chat_create", title: "Hikers", actor: "Esme")?.contains("Esme") == true)
        #expect(ServiceText.sentence(action: "chat_create", title: "Hikers", actor: "Esme")?.contains("Hikers") == true)
        // The affected user is not stored, so these never name anyone.
        #expect(ServiceText.sentence(action: "chat_add_user", title: nil, actor: "Esme")?.contains("Esme") == false)
        #expect(ServiceText.sentence(action: "chat_migrate_to", title: nil, actor: "Esme") == nil)
        #expect(ServiceText.sentence(action: nil, title: nil, actor: nil) == nil)
    }
}

@Suite("Chat titles and avatars")
struct ChatTitleTests {
    @Test("title, else first and last name, else @username, else Deleted account")
    func fallbacks() {
        #expect(ChatTitle.make(title: "Book Club", firstName: "x", lastName: nil, username: "y") == "Book Club")
        #expect(ChatTitle.make(title: nil, firstName: "Juniper", lastName: "Vale", username: "jv") == "Juniper Vale")
        #expect(ChatTitle.make(title: " ", firstName: "Juniper", lastName: nil, username: nil) == "Juniper")
        #expect(ChatTitle.make(title: nil, firstName: nil, lastName: nil, username: "orsonquill") == "@orsonquill")
        #expect(ChatTitle.make(title: nil, firstName: nil, lastName: nil, username: nil)
            == String(localized: "chat.deletedAccount"))
    }

    @Test("Initials take the first letter of the first two words")
    func initials() {
        #expect(AvatarView.initials(of: "Weekend Hikers") == "WH")
        #expect(AvatarView.initials(of: "harbor town weekly") == "HT")
        #expect(AvatarView.initials(of: "@orsonquill") == "O")
        #expect(AvatarView.initials(of: "  ") == "?")
    }

    @Test("The avatar colour is fixed per ref")
    func colour() {
        #expect(AvatarView.paletteIndex(for: "C9uWzfb7MCkzaP28_9kOKA") == AvatarView.paletteIndex(for: "C9uWzfb7MCkzaP28_9kOKA"))
        // FNV-1a of "a" is 0xE40C292C; with eight colours that is index 4.
        #expect(AvatarView.paletteIndex(for: "a") == Int(UInt32(0xE40C_292C) % 8))
        let spread = Set(["a", "b", "c", "d", "e", "f", "g", "h"].map(AvatarView.paletteIndex(for:)))
        #expect(spread.count > 1)
    }
}

@Suite("Relative dates")
struct RelativeDateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let locale = Locale(identifier: "en_US")
    private let now = ArchiveDate.parse("2026-10-07T15:00:00Z")!

    private func string(_ text: String) -> String {
        RelativeDate.string(for: ArchiveDate.parse(text)!, now: now, calendar: calendar, locale: locale)
    }

    @Test("Today is the time, yesterday a word, this week the weekday")
    func recent() {
        #expect(string("2026-10-07T13:48:00Z").contains("1:48"))
        #expect(string("2026-10-07T00:00:00Z").contains("12:00"))
        #expect(string("2026-10-06T23:59:00Z") == String(localized: "date.yesterday"))
        #expect(string("2026-10-04T09:00:00Z") == "Sunday")
        #expect(string("2026-10-01T09:00:00Z") == "Thursday")
    }

    @Test("Older dates this year show day and month; before that the year too")
    func older() {
        #expect(string("2026-09-30T09:00:00Z") == "Sep 30")
        #expect(string("2025-12-31T09:00:00Z") == "Dec 31, 2025")
    }

    @Test("A date ahead of the clock on another day shows the full date")
    func future() {
        #expect(string("2026-10-09T09:00:00Z").contains("2026"))
    }

    @Test("Spanish words and order")
    func spanish() {
        let date = ArchiveDate.parse("2026-09-30T09:00:00Z")!
        let text = RelativeDate.string(for: date, now: now, calendar: calendar, locale: Locale(identifier: "es_ES"))
        #expect(text.hasPrefix("30"))
        #expect(text.contains("sept"))
    }
}

@Suite("Localized strings")
struct LocalizedStringsTests {
    private static func table(_ localization: String) -> [String: String] {
        let bundle = Bundle(for: SessionStore.self)
        guard let path = bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil,
                                     forLocalization: localization),
              let table = NSDictionary(contentsOfFile: path) as? [String: String]
        else { return [:] }
        return table
    }

    @Test("English and Spanish have the same keys")
    func sameKeys() {
        let english = Self.table("en")
        let spanish = Self.table("es")
        #expect(!english.isEmpty)
        #expect(Set(english.keys).subtracting(spanish.keys).sorted() == [])
        #expect(Set(spanish.keys).subtracting(english.keys).sorted() == [])
    }

    @Test("Every key the chat list and topics use is in both tables")
    func chatListKeys() {
        let keys = ["chats.title", "chats.search.prompt", "chats.archived %lld", "chats.archived.title",
                    "chats.archived.empty", "chats.empty", "chats.folders", "chats.folder.all", "chats.forum",
                    "chats.preview.empty", "chats.preview.sender %@ %@%@", "chat.deletedAccount",
                    "chat.placeholder", "list.retry", "date.yesterday", "topics.empty", "topics.untitled",
                    "topics.closed", "topics.pinned", "topics.messageCount %lld", "media.downloadsOff",
                    "media.missing", "media.failed"]
        for localization in ["en", "es"] {
            let table = Self.table(localization)
            for key in keys {
                #expect(table[key] != nil, "\(localization) misses \(key)")
            }
        }
    }
}
