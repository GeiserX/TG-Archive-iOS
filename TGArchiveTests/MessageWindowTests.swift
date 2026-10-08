import Foundation
import Testing
@testable import TGArchive

/// Messages from the committed demo fixtures.
enum ThreadFixture {
    static func messages(_ name: String) throws -> [Message] {
        try ArchiveDecoder.decode(MessagePage.self, from: Fixture.data(name)).messages
    }

    static func message(_ id: Int, in name: String) throws -> Message {
        try #require(try messages(name).first { $0.id == id }, "no message \(id) in \(name)")
    }

    /// A message built from JSON, for the shapes the demo does not have.
    static func decode(_ json: String) throws -> Message {
        try ArchiveDecoder.decode(Message.self, from: Data(json.utf8))
    }

    static func plain(_ id: Int, date: String, sender: Int? = 1, outgoing: Bool = false,
                      extra: String = "") throws -> Message {
        try decode(#"{"id": \#(id), "date": "\#(date)", "text": "m\#(id)", "sender_id": \#(sender.map(String.init) ?? "null"), "#
            + #""is_outgoing": \#(outgoing ? 1 : 0)\#(extra)}"#)
    }
}

@Suite("Message window")
struct MessageWindowTests {
    @Test("The newest page shows oldest first, with more above only when the page came back full")
    func newestPage() throws {
        let page = try ThreadFixture.messages("messages-weekend-hikers")
        let window = MessageWindow(newest: page, full: true)
        #expect(window.messages.first?.id == 1231)
        #expect(window.messages.last?.id == 1275)
        #expect(window.messages.count == page.count)
        #expect(window.hasOlder)
        #expect(!window.hasNewer)
        #expect(!MessageWindow(newest: page, full: false).hasOlder)
    }

    @Test("Pages merge without duplicates, and the copy read last wins")
    func mergeWithoutDuplicates() throws {
        var window = MessageWindow(newest: [try ThreadFixture.plain(2, date: "2026-10-01T10:00:00"),
                                            try ThreadFixture.plain(1, date: "2026-10-01T09:00:00")], full: true)
        let edited = try ThreadFixture.decode(#"{"id": 2, "date": "2026-10-01T10:00:00", "text": "changed"}"#)
        window.addOlder([edited, try ThreadFixture.plain(0, date: "2026-10-01T08:00:00")], full: false)
        #expect(window.messages.map(\.id) == [0, 1, 2])
        #expect(window.messages.last?.text == "changed")
        #expect(!window.hasOlder)
    }

    @Test("Ids are not a time order: the window sorts by date, then id")
    func sortsByDateThenID() throws {
        let page = try ThreadFixture.messages("messages-maker-space")
        let window = MessageWindow(newest: page, full: false)
        let dates = window.messages.map(\.date)
        #expect(dates == dates.sorted())
        #expect(window.messages.last?.id == 29)
        let tie = MessageWindow(newest: [try ThreadFixture.plain(9, date: "2026-10-01T10:00:00"),
                                         try ThreadFixture.plain(4, date: "2026-10-01T10:00:00")], full: false)
        #expect(tie.messages.map(\.id) == [4, 9])
    }

    @Test("The older cursor is the oldest message's date and id; the newer one the highest id")
    func cursors() throws {
        let window = MessageWindow(newest: try ThreadFixture.messages("messages-maker-space"), full: true)
        let oldest = try #require(window.messages.first)
        #expect(window.olderCursor == .before(date: oldest.date, id: oldest.id))
        #expect(window.newerCursor == .after(id: 47))
        #expect(MessageWindow().olderCursor == nil)
        #expect(MessageWindow().newerCursor == nil)
    }

    @Test("An anchored window has newer messages until a newer page comes back short")
    func anchoredNewer() throws {
        var window = MessageWindow(anchored: try ThreadFixture.messages("messages-anchored-before"), full: true)
        #expect(window.hasNewer)
        #expect(window.hasOlder)
        #expect(window.messages.last?.id == 1255)
        window.addNewer(try ThreadFixture.messages("messages-anchored-after"), full: false)
        #expect(!window.hasNewer)
        #expect(window.messages.last?.id == 1275)
        #expect(Set(window.messages.map(\.id)).count == window.messages.count)
    }

    @Test("A day header opens each local day")
    func dayHeaders() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        // 22:30 UTC on the 1st is already the 2nd in Madrid.
        let window = MessageWindow(newest: [try ThreadFixture.plain(3, date: "2026-10-01T22:30:00"),
                                            try ThreadFixture.plain(2, date: "2026-10-01T12:00:00"),
                                            try ThreadFixture.plain(1, date: "2026-10-01T08:00:00")], full: false)
        #expect((0..<3).map { window.startsDay(at: $0, calendar: calendar) } == [true, false, true])
        #expect(!window.startsDay(at: 7, calendar: calendar))
    }

    @Test("A run breaks on another sender, on our own messages and around service rows")
    func runs() throws {
        let window = MessageWindow(newest: [
            try ThreadFixture.plain(6, date: "2026-10-01T10:06:00", sender: 2),
            try ThreadFixture.plain(5, date: "2026-10-01T10:05:00", sender: 2,
                                    extra: #", "raw_data": {"action_type": "chat_edit_photo"}"#),
            try ThreadFixture.plain(4, date: "2026-10-01T10:04:00", sender: 2),
            try ThreadFixture.plain(3, date: "2026-10-01T10:03:00", sender: 9, outgoing: true),
            try ThreadFixture.plain(2, date: "2026-10-01T10:02:00", sender: 1),
            try ThreadFixture.plain(1, date: "2026-10-01T10:01:00", sender: 1),
        ], full: false)
        #expect((0..<6).map { window.startsRun(at: $0) } == [true, false, true, true, true, true])
    }
}

@MainActor
@Suite("Chat thread model")
struct ChatThreadModelTests {
    private let server = MockServer()
    private let recorder = SessionEndRecorder()

    private func model(topicID: Int? = nil, anchor: Int? = nil) -> ChatThreadModel {
        let client = APIClient(server: server.address, cookie: "thread-session",
                               configuration: MockServer.configuration(), cache: MockServer.cache())
        return ChatThreadModel(client: client, ref: "C9uWzfb7MCkzaP28_9kOKA", topicID: topicID, anchor: anchor) {
            [recorder] in recorder.record($0)
        }
    }

    private nonisolated static let messagesPath = "/api/chats/C9uWzfb7MCkzaP28_9kOKA/messages"

    /// The demo group's answers: its row, the newest page, the page before it, and the anchored pages.
    private nonisolated static func archive(_ request: MockServer.Recorded) -> MockServer.Response {
        let name: String? = switch (request.path, request.query["before_date"], request.query["before_id"],
                                    request.query["after_id"]) {
        case ("/api/chats/C9uWzfb7MCkzaP28_9kOKA", _, _, _): "chat"
        case (messagesPath, nil, nil, nil): "messages-weekend-hikers"
        case (messagesPath, _?, "1231", nil): "messages-weekend-hikers-older"
        case (messagesPath, nil, "1256", nil): "messages-anchored-before"
        case (messagesPath, nil, nil, "1255"): "messages-anchored-after"
        default: nil
        }
        guard let name, let response = try? MockServer.Response.fixture(name) else {
            return .json(#"{"detail": "Not Found"}"#, status: 404)
        }
        return response
    }

    @Test("Opening asks for the newest 50 with the cookie, and reads the chat's row beside it")
    func open() async throws {
        server.respond(Self.archive)
        let model = model()
        await model.open()
        let request = try #require(server.requests(to: Self.messagesPath).first)
        #expect(request.query == ["limit": "50"])
        #expect(request.cookie == "viewer_auth=thread-session")
        #expect(model.loaded)
        #expect(model.chat?.displayTitle == "Weekend Hikers")
        #expect(model.showsSenders)
        #expect(model.window.messages.count == 50)
        #expect(model.window.hasOlder)
        #expect(!model.window.hasNewer)
        await model.open()
        #expect(server.requests(to: Self.messagesPath).count == 1)
    }

    @Test("Scrolling up sends the oldest message's date and id, and stops at a short page")
    func older() async throws {
        server.respond(Self.archive)
        let model = model()
        await model.open()
        await model.loadOlder()
        let request = try #require(server.requests(to: Self.messagesPath).last)
        #expect(request.query == ["limit": "50", "before_date": "2026-09-11T17:07:00Z", "before_id": "1231"])
        #expect(model.window.messages.first?.id == 1200)
        #expect(model.window.messages.count == 76)
        #expect(!model.window.hasOlder)
        await model.loadOlder()
        #expect(server.requests(to: Self.messagesPath).count == 2)
    }

    @Test("A forum topic sends topic_id on every page")
    func topic() async throws {
        server.respond { _ in (try? .fixture("messages-maker-space-topic")) ?? .init(status: 500) }
        let model = model(topicID: 39)
        await model.open()
        #expect(server.requests(to: Self.messagesPath).first?.query["topic_id"] == "39")
        #expect(model.window.messages.count == 9)
        #expect(!model.window.hasOlder)
    }

    @Test("An anchor opens at before_id = anchor + 1, then pages newer by the highest id until a short page")
    func anchored() async throws {
        server.respond(Self.archive)
        let model = model(anchor: 1255)
        await model.open()
        #expect(server.requests(to: Self.messagesPath).first?.query == ["limit": "50", "before_id": "1256"])
        #expect(model.window.messages.contains { $0.id == 1255 })
        #expect(model.window.hasNewer)
        await model.loadNewer()
        #expect(server.requests(to: Self.messagesPath).last?.query == ["limit": "50", "after_id": "1255"])
        #expect(!model.window.hasNewer)
        #expect(model.window.messages.last?.id == 1275)
    }

    @Test("Jump to latest leaves the anchor for the newest page")
    func jumpToLatest() async throws {
        server.respond(Self.archive)
        let model = model(anchor: 1255)
        await model.open()
        await model.jumpToLatest()
        #expect(server.requests(to: Self.messagesPath).last?.query == ["limit": "50"])
        #expect(!model.window.hasNewer)
        #expect(model.window.messages.last?.id == 1275)
        #expect(model.window.messages.first?.id == 1231)
    }

    @Test("A 404 marks the chat gone; a 401 ends the session once and shows no error")
    func goneAndEnded() async {
        server.respond { _ in .json(#"{"detail": "Chat not found"}"#, status: 404) }
        let gone = model()
        await gone.open()
        #expect(gone.isUnavailable)
        #expect(gone.error == nil)
        #expect(recorder.clients.isEmpty)

        server.respond { _ in .json(#"{"detail": "Not authenticated"}"#, status: 401) }
        let ended = model()
        await ended.open()
        #expect(recorder.clients.count == 1)
        #expect(recorder.clients.first === ended.client)
        #expect(ended.error == nil)
        #expect(!ended.isUnavailable)
    }

    @Test("A failed older page shows the error, and Retry asks for that page again")
    func retryOlder() async throws {
        server.respond(Self.archive)
        let model = model()
        await model.open()
        server.respond { _ in .json(#"{"detail": "Database not available"}"#, status: 503) }
        await model.loadOlder()
        #expect(model.error == .serverUnavailable(detail: "Database not available"))
        #expect(model.window.messages.count == 50)
        await model.loadOlder()
        #expect(server.requests(to: Self.messagesPath).count == 2)
        server.respond(Self.archive)
        await model.retry()
        #expect(model.error == nil)
        #expect(server.requests(to: Self.messagesPath).last?.query["before_id"] == "1231")
        #expect(model.window.messages.count == 76)
    }

    @Test("A message that does not decode still counts toward a full page")
    func droppedCountsTowardFull() async throws {
        let rows = (1...49).map { #"{"id": \#($0), "date": "2026-10-01T10:00:00"}"# } + [#"{"id": "broken"}"#]
        let body = "[\(rows.joined(separator: ","))]"
        server.respond { request in
            request.path == Self.messagesPath ? .json(body) : .json(#"{"detail": "Not Found"}"#, status: 404)
        }
        let model = model()
        await model.open()
        #expect(model.window.messages.count == 49)
        #expect(model.window.hasOlder)
        #expect(model.chat == nil)
        #expect(!model.showsSenders)
    }
}

@MainActor
@Suite("Message content")
struct MessageContentTests {
    @Test("Every media kind of the demo maps to its cell")
    func kinds() throws {
        func content(_ id: Int, _ name: String) throws -> MessageContent {
            MessageContent(try ThreadFixture.message(id, in: name))
        }
        guard case let .photo(photo) = try content(1274, "messages-anchored-after") else {
            Issue.record("photo"); return
        }
        #expect(photo.key == "1274_photo")
        guard case .video = try content(203, "messages-book-club"),
              case let .video(gif) = try content(204, "messages-book-club"),
              case .videoNote = try content(926, "messages-juniper-vale"),
              case .voice = try content(1265, "messages-anchored-after"),
              case .document = try content(205, "messages-book-club"),
              case let .sticker(still) = try content(1267, "messages-anchored-after"),
              case let .sticker(animated) = try content(1268, "messages-anchored-after"),
              case let .location(geo) = try content(914, "messages-juniper-vale"),
              case let .location(venue) = try content(913, "messages-juniper-vale"),
              case let .location(live) = try content(916, "messages-juniper-vale"),
              case let .contact(contact) = try content(918, "messages-juniper-vale"),
              case let .contact(listed) = try content(74, "messages-mirela-pinecrest"),
              case let .poll(poll) = try content(1266, "messages-anchored-after"),
              case .poll(nil) = try content(911, "messages-juniper-vale"),
              case .none = try content(1275, "messages-anchored-after"),
              case .none = try content(3001, "messages-harbor-town-weekly")
        else {
            Issue.record("a kind mapped to the wrong cell"); return
        }
        #expect(gif.type == .animation)
        #expect(still.isStatic && still.emoji == "☀️")
        #expect(!animated.isStatic && animated.emoji == nil)
        #expect(geo.kind == .geo && geo.hasPoint && geo.mapPicture?.key == "914_geo")
        #expect(venue.title == "Elm Street Bakery" && venue.address == "12 Elm Street, Demo Town")
        #expect(venue.latitude == 40.416775)
        #expect(live.kind == .geoLive && live.mapPicture == nil && live.latitude == 40.41702)
        #expect(contact?.phoneNumber == "15555550100")
        #expect(listed?.firstName == "Sam")
        #expect(poll?.question == "Where should we go next Sunday?")
    }

    @Test("A poll shows its newest state: the snapshot's fields over the first capture's")
    func pollSnapshot() throws {
        guard case let .poll(poll?) = MessageContent(try ThreadFixture.message(1266, in: "messages-anchored-after"))
        else { Issue.record("not a poll"); return }
        #expect(poll.closed == true)
        #expect(poll.results?.totalVoters == 14)
        #expect(poll.rows.map(\.text) == ["Pine Lake loop", "Ridge trail again", "Coastal path"])
        #expect(poll.rows.map(\.voters) == [8, 2, 4])
        #expect(abs((poll.rows.first?.fraction ?? 0) - 8.0 / 14.0) < 0.0001)

        let first = Poll(question: "Q", answers: [PollAnswer(text: "A", option: "MA==")], closed: false,
                         multipleChoice: true, quiz: false,
                         results: PollResults(totalVoters: 1, results: [PollOptionResult(option: "MA==", voters: 1,
                                                                                         correct: nil)]))
        let resultsOnly = Poll(question: nil, answers: nil, closed: nil, multipleChoice: nil, quiz: nil,
                               results: PollResults(totalVoters: 3, results: [PollOptionResult(option: "MA==",
                                                                                              voters: 3, correct: nil)]))
        let merged = try #require(Poll.newest(raw: first, snapshot: resultsOnly))
        #expect(merged.question == "Q")
        #expect(merged.multipleChoice == true)
        #expect(merged.rows.first?.voters == 3)
        #expect(merged.rows.first?.fraction == 1)
        #expect(Poll.newest(raw: nil, snapshot: nil) == nil)
    }

    @Test("Files that are not fetched say why, and downloads off wins")
    func unavailable() throws {
        let tokenMedia = try ThreadFixture.messages("token-messages").compactMap(\.media)
        #expect(!tokenMedia.isEmpty)
        #expect(tokenMedia.allSatisfy { MediaUnavailable.reason(for: $0, noDownload: false) == .downloadsOff })

        let book = try ThreadFixture.messages("messages-book-club").compactMap(\.media)
            + ThreadFixture.messages("messages-weekend-hikers-older").compactMap(\.media)
            + ThreadFixture.messages("messages-orson-quill").compactMap(\.media)
            + ThreadFixture.messages("messages-platform-team").compactMap(\.media)
        let reasons = Set(book.compactMap { MediaUnavailable.reason(for: $0, noDownload: false) })
        #expect(reasons.isSuperset(of: [.tooLarge, .filtered]))

        let photo = try #require(try ThreadFixture.message(1274, in: "messages-anchored-after").media)
        #expect(MediaUnavailable.reason(for: photo, noDownload: false) == nil)
        #expect(MediaUnavailable.reason(for: photo, noDownload: true) == .downloadsOff)
        let waiting = try ThreadFixture.decode(#"{"id": 1, "date": "2026-10-01T10:00:00", "media": "#
            + #"{"id": "1_photo", "type": "photo", "url": null, "downloaded": 0, "skip_reason": null}}"#)
        #expect(MediaUnavailable.reason(for: try #require(waiting.media), noDownload: false) == .notDownloaded)
    }

    @Test("Live reactions get a chip each, custom ones a sparkle, and the taken-back ones fold into one count")
    func reactions() throws {
        let message = try ThreadFixture.message(1269, in: "messages-anchored-after")
        let summary = ReactionSummary(reactions: message.reactions, removed: message.removedReactions)
        #expect(summary.chips.map(\.emoji) == [nil, nil, nil, "❤️", "🔥", "😮"])
        #expect(summary.chips.map(\.count) == [3, 2, 1, 5, 1, 1])
        #expect(summary.takenBack == 3)
        #expect(ReactionSummary(reactions: [], removed: nil).isEmpty)
    }

    @Test("A reply quotes the sender and text, or a label for the media kind; a topic root is not quoted")
    func replyQuote() throws {
        let reply = try #require(ReplyQuote(try ThreadFixture.message(1262, in: "messages-anchored-after"),
                                            topicID: nil))
        #expect(reply.sender == "Kofi Brightwater")
        #expect(reply.text == "Which trailhead did you park at?")
        let toPhoto = try ThreadFixture.decode(#"{"id": 5, "date": "2026-10-01T10:00:00", "reply_to_msg_id": 4, "#
            + #""reply_to_media_type": "photo"}"#)
        #expect(ReplyQuote(toPhoto, topicID: nil)?.text == String(localized: "preview.kind.photo"))
        let inTopic = try ThreadFixture.decode(#"{"id": 6, "date": "2026-10-01T10:00:00", "reply_to_msg_id": 39, "#
            + #""reply_to_sender_name": "Dax", "reply_to_text": ""}"#)
        #expect(ReplyQuote(inTopic, topicID: 39) == nil)
        #expect(ReplyQuote(try ThreadFixture.message(1275, in: "messages-anchored-after"), topicID: nil) == nil)
    }

    @Test("The edited, deleted and forward marks read as the archive keeps them")
    func marks() throws {
        let edited = try ThreadFixture.message(1270, in: "messages-anchored-after")
        #expect(edited.isEdited)
        let deleted = try ThreadFixture.message(1274, in: "messages-anchored-after")
        #expect(deleted.isDeleted)
        let forwarded = try ThreadFixture.message(1264, in: "messages-anchored-after")
        #expect(forwarded.rawData?.forwardFromName == "Harbor Town Weekly")
        let hidden = try ThreadFixture.decode(#"{"id": 1, "date": "2026-10-01T10:00:00", "edit_date": "#
            + #""2026-10-01T10:05:00", "edit_hide": 1}"#)
        #expect(!hidden.isEdited)
    }

    @Test("Durations, file names and transcripts read as the cells show them")
    func cellText() throws {
        #expect(MediaFrame.duration(14) == "0:14")
        #expect(MediaFrame.duration(3725) == "1:02:05")
        #expect(MediaFrame.duration(nil) == nil)
        #expect(DocumentName.display("1543569123_seating-plan.png") == "seating-plan.png")
        #expect(DocumentName.display("notes_v2.txt") == "notes_v2.txt")
        #expect(DocumentName.display("  ") == nil)
        #expect(ContactCell.phone("15555550100") == "+15555550100")
        let voice = try #require(try ThreadFixture.message(1265, in: "messages-anchored-after").media)
        #expect(TranscriptView.text(of: voice)?.hasPrefix("Quick update on Sunday.") == true)
        let pending = try ThreadFixture.decode(#"{"id": 1, "date": "2026-10-01T10:00:00", "media": {"id": "1_voice", "#
            + #""type": "voice", "transcripts": [{"status": "pending", "text": null}, "#
            + #"{"status": "done", "text": "older"}, {"status": "done", "text": "oldest"}]}}"#)
        #expect(TranscriptView.text(of: try #require(pending.media)) == "older")
    }

    @Test("A poll reads its question, answers and votes from raw_data, and one kept without them is empty")
    func pollDetails() throws {
        guard case let .poll(poll?) = MessageContent(try ThreadFixture.message(337, in: "messages-book-club")),
              case .poll(nil) = MessageContent(try ThreadFixture.message(911, in: "messages-juniper-vale"))
        else { Issue.record("not a poll"); return }
        #expect(!poll.isEmpty)
        #expect(poll.question == "Which book should we read in spring?")
        #expect(poll.rows.map(\.text) == ["The Salt Orchard", "Winter Lines"])
        #expect(poll.rows.map(\.voters) == [2, 1])
        #expect(poll.results?.totalVoters == 3)
        #expect(poll.closed == false)
        let empty = Poll(question: " ", answers: [], closed: nil, multipleChoice: nil, quiz: nil, results: nil)
        #expect(empty.isEmpty)
        let answersOnly = Poll(question: nil, answers: [PollAnswer(text: "A", option: "MA==")], closed: nil,
                               multipleChoice: nil, quiz: nil, results: nil)
        #expect(!answersOnly.isEmpty)
    }

    @Test("The three location kinds give a point, coordinates and a Maps link; a map picture needs its file name")
    func locationDetails() throws {
        func location(_ id: Int) throws -> LocationContent {
            guard case let .location(content) = MessageContent(try ThreadFixture.message(id, in: "messages-juniper-vale"))
            else { throw LocationFixtureError.notALocation(id) }
            return content
        }
        let geo = try location(914)
        #expect(geo.mapPicture?.key == "914_geo")
        #expect(geo.coordinates == "40.419020, -3.700910")
        #expect(geo.unavailableText == nil && geo.mapsURL != nil)
        let venue = try location(913)
        #expect(venue.mapPicture?.key == "913_venue")
        #expect(venue.title == "Elm Street Bakery" && venue.address == "12 Elm Street, Demo Town")
        #expect(venue.mapsURL?.query()?.contains("q=Elm%20Street%20Bakery") == true)
        let live = try location(916)
        #expect(live.mapPicture == nil)
        #expect(live.coordinates == "40.417020, -3.703220")
        #expect(live.unavailableText == nil && live.mapsURL != nil)

        #expect(LocationContent.isMapPicture("map_4b0f0ddad4d8c9d1.png"))
        #expect(LocationContent.isMapPicture("MAP_4B0F0DDAD4D8C9D1.JPG"))
        #expect(!LocationContent.isMapPicture("194825724.bin"))
        #expect(!LocationContent.isMapPicture("map_4b0f.png"))
        #expect(!LocationContent.isMapPicture("map_4b0f0ddad4d8c9d1.png.bin"))
        #expect(!LocationContent.isMapPicture(nil))
        let served = try ThreadFixture.decode(#"{"id": 2, "date": "2026-10-01T10:00:00", "raw_data": {"geo": "#
            + #"{"lat": 1.5, "long": 2.25}}, "media": {"id": "2_geo", "type": "geo", "file_name": "2.bin", "#
            + #""url": "/media/x/2_geo"}}"#)
        guard case let .location(notAPicture) = MessageContent(served) else { Issue.record("not a location"); return }
        #expect(notAPicture.mapPicture == nil)
        #expect(notAPicture.coordinates == "1.500000, 2.250000")
    }

    @Test("A location with nothing to draw says why: no payload kept, or no usable point")
    func locationUnavailable() throws {
        guard case let .location(legacy) = MessageContent(try ThreadFixture.message(910, in: "messages-juniper-vale"))
        else { Issue.record("not a location"); return }
        #expect(!legacy.hasDetails && legacy.mapPicture == nil && legacy.mapsURL == nil)
        #expect(legacy.unavailableText == String(localized: "chat.media.detailsNotArchived"))
        let noPoint = try ThreadFixture.decode(#"{"id": 3, "date": "2026-10-01T10:00:00", "raw_data": {"geo": "#
            + #"{"lat": 91, "long": 2}}}"#)
        guard case let .location(bad) = MessageContent(noPoint) else { Issue.record("not a location"); return }
        #expect(bad.hasDetails && !bad.hasPoint && bad.coordinates == nil)
        #expect(bad.unavailableText == String(localized: "chat.location.unavailable"))
    }

    @Test("A location builds an Apple Maps link only when it has a point")
    func mapsLink() throws {
        guard case let .location(venue) = MessageContent(try ThreadFixture.message(913, in: "messages-juniper-vale"))
        else { Issue.record("not a location"); return }
        let url = try #require(venue.mapsURL)
        #expect(url.host() == "maps.apple.com")
        #expect(url.query()?.contains("ll=40.416775,-3.70379") == true)
        let noPoint = LocationContent(kind: .geo, raw: nil, media: nil)
        #expect(noPoint.mapsURL == nil)
        #expect(!noPoint.hasPoint)
    }
}

private enum LocationFixtureError: Error {
    case notALocation(Int)
}
