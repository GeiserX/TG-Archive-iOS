import Foundation
import SwiftUI
import Testing
@testable import TGArchive

@Suite("Entity text")
struct EntityTextTests {
    private func entity(_ type: String, _ offset: Int, _ length: Int, url: String? = nil) throws -> Entity {
        let link = url.map { #", "url": "\#($0)""# } ?? ""
        return try ArchiveDecoder.decode(
            Entity.self, from: Data(#"{"type": "\#(type)", "offset": \#(offset), "length": \#(length)\#(link)}"#.utf8))
    }

    /// The characters of every run that carries `predicate`, joined.
    private func text(of string: AttributedString, where predicate: (AttributedString.Runs.Run) -> Bool) -> String {
        string.runs.filter(predicate).map { String(string[$0.range].characters) }.joined()
    }

    @Test("Offsets count UTF-16 units, so an emoji before a bold span does not shift it")
    func utf16Offsets() throws {
        // "🌞" is two UTF-16 units.
        let string = EntityText.attributed("🌞 hot day", entities: [try entity("bold", 3, 3)])
        #expect(text(of: string) { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true } == "hot")
        #expect(String(string.characters) == "🌞 hot day")
    }

    @Test("Bold inside italic keeps both")
    func nested() throws {
        let string = EntityText.attributed("very bold words",
                                           entities: [try entity("italic", 0, 15), try entity("bold", 5, 4)])
        let both = text(of: string) { $0.inlinePresentationIntent == [.emphasized, .stronglyEmphasized] }
        #expect(both == "bold")
        #expect(text(of: string) { $0.inlinePresentationIntent == .emphasized } == "very  words")
    }

    @Test("Underline, strikethrough, code and pre each style their span")
    func styles() throws {
        let string = EntityText.attributed("u s c p", entities: [
            try entity("underline", 0, 1), try entity("strikethrough", 2, 1),
            try entity("code", 4, 1), try entity("pre", 6, 1),
        ])
        #expect(text(of: string) { $0.underlineStyle != nil } == "u")
        #expect(text(of: string) { $0.strikethroughStyle != nil } == "s")
        #expect(text(of: string) { $0.inlinePresentationIntent == .code } == "cp")
    }

    @Test("Web links become tappable; a bare host gets https; app links do not")
    func links() throws {
        let string = EntityText.attributed("see example.org or here or there", entities: [
            try entity("url", 4, 11), try entity("text_url", 19, 4, url: "https://example.com/a"),
            try entity("text_url", 27, 5, url: "tg://resolve?domain=x"),
        ])
        let links = string.runs.compactMap(\.link)
        #expect(links == [URL(string: "https://example.org")!, URL(string: "https://example.com/a")!])
        #expect(EntityText.link("javascript:alert(1)") == nil)
        #expect(EntityText.link("http://a b") == nil)
        #expect(EntityText.link("HTTP://Example.org/x")?.host() == "Example.org")
    }

    @Test("Mentions and hashtags are coloured, never links")
    func mentions() throws {
        let string = EntityText.attributed("@robin #hike", entities: [try entity("mention", 0, 6),
                                                                      try entity("hashtag", 7, 5)])
        #expect(string.runs.allSatisfy { $0.link == nil })
        #expect(text(of: string) { $0.foregroundColor != nil } == "@robin#hike")
    }

    @Test("A custom emoji keeps the ordinary emoji already in the text")
    func customEmoji() throws {
        let message = try ThreadFixture.message(1270, in: "messages-anchored-after")
        let string = EntityText.attributed(try #require(message.text), entities: message.rawData?.entities)
        #expect(String(string.characters) == "Same sun from the summit 🌞")
    }

    @Test("An entity out of bounds or splitting an emoji is skipped, and the text stays whole")
    func outOfBounds() throws {
        let string = EntityText.attributed("🌞ab", entities: [
            try entity("bold", 1, 2), try entity("italic", 2, 10), try entity("code", -1, 2),
            try entity("underline", 3, 0),
        ])
        #expect(String(string.characters) == "🌞ab")
        #expect(string.runs.allSatisfy { $0.inlinePresentationIntent == nil && $0.underlineStyle == nil })
        #expect(EntityText.attributed("plain", entities: nil) == AttributedString("plain"))
    }
}
