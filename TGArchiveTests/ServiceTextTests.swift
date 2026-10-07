import Foundation
import Testing
@testable import TGArchive

/// The thread's wording of service rows, with the sender's name, from the server's own table.
@Suite("Service text")
struct ServiceTextTests {
    private func service(_ action: String?, title: String? = nil, text: String = "",
                         sender: String? = "Ada Pine") throws -> Message {
        let titleJSON = title.map { #", "new_title": "\#($0)""# } ?? ""
        let actionJSON = action.map { #""action_type": "\#($0)""# } ?? #""action_type": null"#
        let senderJSON = sender.map { #""\#($0)""# } ?? "null"
        return try ThreadFixture.decode(#"{"id": 1, "date": "2026-10-01T10:00:00", "text": "\#(text)", "#
            + #""sender_name": \#(senderJSON), "raw_data": {"service_type": "service", \#(actionJSON)\#(titleJSON)}}"#)
    }

    @Test("A join by link names the sender, as the demo's oldest hiking message does")
    func joinedByLink() throws {
        let message = try ThreadFixture.message(1200, in: "messages-weekend-hikers-older")
        #expect(message.isService)
        #expect(message.serviceSentence == String(localized: "service.joinedByLink.actor \("Orson Quill")"))
        #expect(message.serviceSentence?.hasPrefix("Orson Quill") == true)
    }

    @Test("Title actions quote the new title, with or without one")
    func titles() throws {
        #expect(try service("chat_edit_title", title: "Trail Crew").serviceSentence
            == String(localized: "service.editTitle.actor \("Ada Pine") \("Trail Crew")"))
        #expect(try service("channel_create", title: "News").serviceSentence
            == String(localized: "service.channelCreate.actor \("Ada Pine") \("News")"))
        #expect(try service("chat_create").serviceSentence
            == String(localized: "service.chatCreateUnknown.actor \("Ada Pine")"))
    }

    @Test("Added and removed name nobody: the affected user is not stored")
    func unknownSubject() throws {
        #expect(try service("chat_add_user").serviceSentence == String(localized: "service.addUser"))
        #expect(try service("chat_delete_user", sender: nil).serviceSentence == String(localized: "service.deleteUser"))
    }

    @Test("A stored sentence wins; an action the table lacks leaves the glyph alone")
    func storedAndUnmapped() throws {
        #expect(try service("chat_edit_photo", text: "Ada changed the photo").serviceSentence == "Ada changed the photo")
        let topic = try ThreadFixture.message(39, in: "messages-maker-space-topic")
        #expect(topic.isService)
        #expect(topic.serviceSentence == nil)
        #expect(try service(nil).serviceSentence == nil)
        #expect(try service("chat_edit_photo", sender: nil).serviceSentence == String(localized: "service.editPhoto"))
    }

    @Test("Ordinary messages are not service rows")
    func notService() throws {
        #expect(!(try ThreadFixture.message(1275, in: "messages-anchored-after")).isService)
    }
}
