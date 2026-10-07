import Foundation
import Testing
@testable import TGArchive

@Suite("Decoding the archive's JSON")
struct DecodingTests {
    /// The model each committed fixture decodes into. A fixture missing from here and from `unmodeled` fails
    /// `everyFixtureIsCovered`, so a new capture cannot slip past the decoding tests.
    private static let models: [String: any (Decodable & Sendable).Type] = [
        "archived-count": ArchivedCount.self,
        "auth-check": AuthCheck.self,
        "auth-check-after-logout": AuthCheck.self,
        "auth-check-signed-out": AuthCheck.self,
        "auth-check-token": AuthCheck.self,
        "chat": Chat.self,
        "chats": ChatsPage.self,
        "chats-archived": ChatsPage.self,
        "token-chats": ChatsPage.self,
        "error-401": ErrorBody.self,
        "error-403": ErrorBody.self,
        "error-404": ErrorBody.self,
        "login-401": ErrorBody.self,
        "folders": FolderList.self,
        "health": Health.self,
        "login": LoginResponse.self,
        "token-login": LoginResponse.self,
        "logout": LoginResponse.self,
        "pinned": MessagePage.self,
        "token-messages": MessagePage.self,
        "search": SearchPage.self,
        "search-topics": SearchPage.self,
        "stats": ArchiveStats.self,
        "topics": TopicList.self,
    ]

    /// Routes v1 does not call (section 7 of the design): chat stats, custom emoji, message versions.
    private static let unmodeled: Set<String> = ["chat-stats", "custom-emoji", "versions", "versions-media"]

    private static func model(for name: String) -> (any (Decodable & Sendable).Type)? {
        name.hasPrefix("messages-") ? MessagePage.self : models[name]
    }

    private static func decode<T: Decodable>(_ type: T.Type, _ fixture: String) throws -> T {
        try ArchiveDecoder.decode(type, from: Fixture.data(fixture))
    }

    private static var messageFixtures: [String] {
        Fixture.names().filter { $0.hasPrefix("messages-") } + ["token-messages", "pinned"]
    }

    private static func allMessages() throws -> [Message] {
        try messageFixtures.flatMap { try decode(MessagePage.self, $0).messages }
    }

    @Test("Every committed fixture is either decoded below or deliberately unmodeled")
    func everyFixtureIsCovered() {
        let names = Fixture.names()
        #expect(names.count >= 40, "the fixtures are not in the test bundle")
        let uncovered = names.filter { Self.model(for: $0) == nil && !Self.unmodeled.contains($0) }
        #expect(uncovered.isEmpty, "fixtures with no model: \(uncovered)")
    }

    @Test("Every fixture decodes into its model", arguments: Fixture.names())
    func fixtureDecodes(_ name: String) throws {
        guard let type = Self.model(for: name) else { return }
        _ = try Self.decode(type, name)
    }

    @Test("No message in any fixture is dropped")
    func noMessageDropped() throws {
        for name in Self.messageFixtures {
            let page = try Self.decode(MessagePage.self, name)
            #expect(page.dropped == 0, "\(name) dropped \(page.dropped)")
            #expect(!page.messages.isEmpty, "\(name) is empty")
        }
    }

    @Test("The chat list: an object with paging, previews, null titles and integer flags")
    func chatList() throws {
        let page = try Self.decode(ChatsPage.self, "chats")
        #expect(page.chats.count == 14)
        #expect(page.total == 14)
        #expect(page.hasMore == false)

        let hikers = try #require(page.chats.first)
        #expect(hikers.title == "Weekend Hikers")
        #expect(hikers.type == "group")
        #expect(hikers.avatarURL == "/media/avatar/\(hikers.ref)")
        let preview = try #require(hikers.preview)
        #expect(preview.messageID == 1275)
        #expect(preview.sender == "Esme")
        #expect(preview.kind == "text")
        #expect(preview.outgoing == false)
        #expect(preview.date == Date(timeIntervalSince1970: 1_791_380_880)) // 2026-10-07T13:48:00Z

        let juniper = try #require(page.chats.first { $0.firstName == "Juniper" })
        #expect(juniper.title == nil)
        #expect(juniper.lastName == "Vale")
        #expect(juniper.preview?.kind == "voice")
        #expect(juniper.preview?.text == nil)

        #expect(page.chats.filter(\.isForum).map(\.title) == ["Maker Space"])
        #expect(page.chats.allSatisfy { !$0.isArchived })

        let archived = try Self.decode(ChatsPage.self, "chats-archived")
        #expect(!archived.chats.isEmpty)
        #expect(archived.chats.allSatisfy { $0.isArchived })
        #expect(try Self.decode(ArchivedCount.self, "archived-count").count == 1)
    }

    @Test("Auth check, login and token login carry role, user and the download flag")
    func authAnswers() throws {
        let master = try Self.decode(AuthCheck.self, "auth-check")
        #expect(master.authenticated && master.authRequired)
        #expect(master.role == "master")
        #expect(master.noDownload == false)

        let token = try Self.decode(AuthCheck.self, "auth-check-token")
        #expect(token.role == "token")
        #expect(token.username == "token:Hike photos")
        #expect(token.noDownload == true)

        let signedOut = try Self.decode(AuthCheck.self, "auth-check-signed-out")
        #expect(!signedOut.authenticated && signedOut.authRequired)
        #expect(signedOut.role == nil)

        #expect(try Self.decode(LoginResponse.self, "login").role == "master")
        #expect(try Self.decode(LoginResponse.self, "token-login").noDownload == true)
        #expect(try Self.decode(ErrorBody.self, "login-401").detail == "Invalid credentials")
    }

    @Test("A body without the two auth flags is not an archive server's auth check")
    func authCheckNeedsItsFlags() {
        #expect(throws: APIError.self) { try ArchiveDecoder.decode(AuthCheck.self, from: Data("{}".utf8)) }
        #expect(throws: APIError.self) {
            try ArchiveDecoder.decode(AuthCheck.self, from: Data("<html><body>hello</body></html>".utf8))
        }
    }

    @Test("Folders, topics, stats and health")
    func smallRoutes() throws {
        let folders = try Self.decode(FolderList.self, "folders").folders
        #expect(folders.map(\.title) == ["Friends", "Hobbies"])
        #expect(folders.first?.chatCount == 6)

        let topics = try Self.decode(TopicList.self, "topics").topics
        let events = try #require(topics.first { $0.title == "Events" })
        #expect(events.isPinned && !events.isClosed && !events.isHidden)
        #expect(events.iconEmoji == "📅")
        #expect(events.messageCount == 9)
        #expect(topics.first { $0.title == "Woodworking" }?.isClosed == true)

        let stats = try Self.decode(ArchiveStats.self, "stats")
        #expect(stats.messages == 409)
        #expect(stats.mediaFiles == 46)
        #expect(stats.showStats == true)
        #expect(stats.lastBackupTime == Date(timeIntervalSince1970: 1_791_380_040)) // 2026-10-07T13:34:00Z

        #expect(try Self.decode(Health.self, "health").status == "ok")
    }

    @Test("Search: boolean flags, the chat of each hit, topic titles")
    func search() throws {
        let page = try Self.decode(SearchPage.self, "search")
        #expect(page.hasMore && page.indexed)
        #expect(page.results.count == 20)
        let first = try #require(page.results.first)
        #expect(first.id == 1272)
        #expect(first.isDeleted)
        #expect(first.chat.title == "Weekend Hikers")
        #expect(first.chat.isForum == false)

        let topics = try Self.decode(SearchPage.self, "search-topics")
        #expect(topics.results.contains { $0.topicTitle != nil && $0.chat.isForum })
    }

    @Test("Messages hold every kind the demo makes, with its details")
    func messageKinds() throws {
        let messages = try Self.allMessages()
        let kinds = Set(messages.compactMap { $0.media?.type })
        let expected: Set<MediaType> = [.photo, .video, .videoNote, .voice, .animation, .sticker, .document,
                                        .geo, .venue, .contact, .poll]
        #expect(expected.isSubset(of: kinds), "missing \(expected.subtracting(kinds))")
        #expect(!kinds.contains(.unsupported))

        let geo = try #require(messages.first { $0.rawData?.geo != nil }?.rawData?.geo)
        #expect(geo.lat != nil && geo.long != nil)
        let venue = try #require(messages.first { $0.rawData?.venue != nil }?.rawData?.venue)
        #expect(venue.title?.isEmpty == false)
        let live = try #require(messages.first { $0.rawData?.geoLive != nil }?.rawData?.geoLive)
        #expect(live.period != nil && live.at != nil)
        let contact = try #require(messages.first { $0.rawData?.contact != nil }?.rawData?.contact)
        #expect(contact.phoneNumber?.isEmpty == false)
        #expect(messages.contains { $0.rawData?.sticker?.emoji != nil })
        #expect(messages.contains { $0.rawData?.forwardFromName != nil })
        #expect(messages.contains { $0.rawData?.actionType == "chat_joined_by_link" })
        #expect(messages.contains { $0.replyToSenderName != nil && $0.replyToMsgID != nil })
        #expect(messages.contains { $0.isDeleted })
        #expect(messages.contains { $0.isPinned })
        #expect(messages.contains { $0.isOutgoing })
        #expect(messages.contains { $0.isEdited })

        let photo = try #require(messages.first { $0.media?.type == .photo && $0.media?.url != nil }?.media)
        #expect(photo.key == photo.url?.split(separator: "/").last.map(String.init))
        #expect(photo.width != nil && photo.height != nil)
        #expect(messages.contains { $0.media?.skipReason == "oversize" })
        #expect(messages.contains { $0.media?.skipReason == "filtered" })
    }

    @Test("Album ids decode from numbers; custom emoji ids stay strings")
    func idsAsStrings() throws {
        let messages = try Self.allMessages()
        #expect(messages.contains { $0.rawData?.groupedID?.isEmpty == false })
        let entity = try #require(messages.flatMap { $0.rawData?.entities ?? [] }.first { $0.type == "custom_emoji" })
        #expect(entity.documentID?.hasPrefix("5000000000") == true)
        #expect(entity.length > 0)

        let json = #"[{"id": 1, "date": "2026-10-07T10:00:00", "raw_data": {"grouped_id": "13800000000000001"}}]"#
        let page = try ArchiveDecoder.decode(MessagePage.self, from: Data(json.utf8))
        #expect(page.messages.first?.rawData?.groupedID == "13800000000000001")
    }

    @Test("Poll, its later snapshot, transcripts and reactions taken back")
    func pollTranscriptsReactions() throws {
        let messages = try Self.allMessages()
        let poll = try #require(messages.first { $0.rawData?.poll != nil && $0.snapshots?.poll != nil })
        #expect(poll.rawData?.poll?.closed == false)
        #expect(poll.rawData?.poll?.answers?.count == 3)
        #expect(poll.rawData?.poll?.results?.totalVoters == 11)
        let snapshot = try #require(poll.snapshots?.poll)
        #expect(snapshot.payload?.closed == true)
        #expect(snapshot.payload?.results?.totalVoters == 14)
        #expect(snapshot.differsFromFirst == true)

        let transcripts: [Transcript] = messages.compactMap { $0.media?.transcripts?.first }
        let transcript = try #require(transcripts.first)
        #expect(transcript.status == "done")
        #expect(transcript.text?.isEmpty == false)
        #expect(transcript.language == "en")

        let removedReactions: [RemovedReaction] = messages.compactMap { $0.removedReactions?.first }
        let removed = try #require(removedReactions.first)
        #expect(removed.count > 0)
        #expect(removed.countBefore != nil)
        #expect(removed.removedAt != nil)
        #expect(messages.contains { ($0.reactions ?? []).contains { $0.emoji.hasPrefix("custom_") } })
    }

    @Test("A share link with downloads off gets no media URLs")
    func noDownloadMessages() throws {
        let page = try Self.decode(MessagePage.self, "token-messages")
        let media = page.messages.compactMap(\.media)
        #expect(!media.isEmpty)
        #expect(media.allSatisfy { $0.url == nil })
        #expect(media.contains { $0.noDownload == true })
    }

    @Test("One odd message is dropped and counted; odd parts of a message read as nil")
    func lenientMessages() throws {
        let json = #"""
        [
          {"id": 3, "date": "2026-10-07T10:00:00", "media": {"id": "3_hologram", "type": "hologram", "downloaded": 1}},
          {"id": "not a number", "date": "2026-10-07T10:00:00"},
          {"id": 2, "date": "2026-10-07T09:00:00", "raw_data": "garbage", "reactions": {"oops": true},
           "is_outgoing": true, "is_deleted": null},
          {"id": 1, "date": "not a date"},
          null,
          42
        ]
        """#
        let page = try ArchiveDecoder.decode(MessagePage.self, from: Data(json.utf8))
        #expect(page.messages.map(\.id) == [3, 2])
        #expect(page.dropped == 4)
        #expect(page.messages[0].media?.type == .unsupported)
        #expect(page.messages[0].media?.downloaded == true)
        #expect(page.messages[1].rawData == nil)
        #expect(page.messages[1].reactions == nil)
        #expect(page.messages[1].isOutgoing)
        #expect(!page.messages[1].isDeleted)
        #expect(!page.messages[1].isPinned)
    }

    @Test("The edited mark follows the server's pencil rule")
    func editedRule() throws {
        func message(_ fields: String) throws -> Message {
            let json = #"[{"id": 1, "date": "2026-10-07T10:00:00"\#(fields)}]"#
            return try #require(ArchiveDecoder.decode(MessagePage.self, from: Data(json.utf8)).messages.first)
        }
        let cases: [(String, Bool)] = [
            ("", false),
            (#", "edit_date": "2026-10-07T10:05:00""#, true),
            (#", "edit_date": "2026-10-07T10:05:00", "edit_hide": null"#, true),
            (#", "edit_date": "2026-10-07T10:05:00", "edit_hide": 0"#, true),
            (#", "edit_date": "2026-10-07T10:05:00", "edit_hide": 1"#, false),
            (#", "edit_date": "2026-10-07T10:05:00", "edit_hide": 1, "version_count": 2"#, true),
            (#", "version_count": 1"#, true),
            (#", "version_count": 0"#, false),
        ]
        for (fields, edited) in cases {
            let isEdited = try message(fields).isEdited
            #expect(isEdited == edited, "\(fields)")
        }
    }

    private struct Flags: Decodable {
        @FlexBool var flag: Bool
    }

    @Test("FlexBool reads 0, 1, true, false, null and a missing key",
          arguments: [("0", false), ("1", true), ("2", true), ("true", true), ("false", false), ("null", false)])
    func flexBool(_ raw: String, _ expected: Bool) throws {
        let flags = try ArchiveDecoder.decode(Flags.self, from: Data(#"{"flag": \#(raw)}"#.utf8))
        #expect(flags.flag == expected)
    }

    @Test("FlexBool: a missing key is false, a string fails")
    func flexBoolEdges() throws {
        #expect(try ArchiveDecoder.decode(Flags.self, from: Data("{}".utf8)).flag == false)
        #expect(throws: APIError.self) { try ArchiveDecoder.decode(Flags.self, from: Data(#"{"flag": "yes"}"#.utf8)) }
    }

    @Test("Dates: ISO 8601 with or without fractions and offsets; no offset means UTC",
          arguments: [
              ("2026-10-07T13:48:00", 1_791_380_880.0),
              ("2026-10-07T13:48:00Z", 1_791_380_880.0),
              ("2026-10-07T13:48:00+00:00", 1_791_380_880.0),
              ("2026-10-07T15:48:00+02:00", 1_791_380_880.0),
              ("2026-10-07T08:48:00-0500", 1_791_380_880.0),
              ("2026-10-07 13:48:00", 1_791_380_880.0),
              ("2026-10-07T13:48", 1_791_380_880.0),
              ("2026-10-07T13:48:00.5", 1_791_380_880.5),
              ("2026-10-07T13:48:00.250000Z", 1_791_380_880.25),
              ("1970-01-01T00:00:00", 0.0),
              ("2024-02-29T12:00:00", 1_709_208_000.0),
          ])
    func dates(_ text: String, _ seconds: Double) throws {
        let date = try #require(ArchiveDate.parse(text))
        #expect(abs(date.timeIntervalSince1970 - seconds) < 0.000_5)
    }

    @Test("Dates that are not ISO 8601 do not parse",
          arguments: ["", "yesterday", "2026-10-07", "2026-13-07T10:00:00", "2026-10-07T10:00:00+2", "1791381660",
                      "2026-10-07T10:00:00Zjunk"])
    func badDates(_ text: String) {
        #expect(ArchiveDate.parse(text) == nil)
    }

    @Test("A cursor date goes back as UTC with Z")
    func cursorDateFormat() throws {
        let date = try #require(ArchiveDate.parse("2026-10-07T13:48:00"))
        #expect(ArchiveDate.format(date) == "2026-10-07T13:48:00Z")
    }

    @Test("A decoding error names the path, never the value")
    func decodingErrorHidesValues() {
        let json = #"[{"id": 1, "date": "secret-looking-value"}]"#
        do {
            _ = try ArchiveDecoder.decode([Message].self, from: Data(json.utf8))
            Issue.record("expected a decoding error")
        } catch {
            guard case let .decoding(description) = error else {
                Issue.record("expected .decoding, got \(error)")
                return
            }
            #expect(description.contains("date"))
            #expect(!description.contains("secret-looking-value"))
        }
    }
}
