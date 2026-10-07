import Foundation
import SwiftUI

/// A message's text with its Telegram formatting (`raw_data.entities`) as an `AttributedString`.
///
/// Entities count UTF-16 code units, as Telegram does. An entity that falls outside the text or splits a
/// character is skipped rather than guessed at. A custom emoji keeps the characters in the text, which
/// Telegram sets to the ordinary emoji it stands for. Only web and mail links become tappable: a `tg:` or
/// other app link from the archive would leave the app for somewhere it cannot follow.
enum EntityText {
    static func attributed(_ text: String, entities: [Entity]?) -> AttributedString {
        var result = AttributedString(text)
        for entity in entities ?? [] {
            guard let span = stringRange(of: entity, in: text), let range = Range(span, in: result) else { continue }
            apply(entity, text: String(text[span]), to: &result, in: range)
        }
        return result
    }

    /// The entity's span as a `String` range, or nil when it is out of bounds or not on character boundaries.
    static func stringRange(of entity: Entity, in text: String) -> Range<String.Index>? {
        guard entity.offset >= 0, entity.length > 0 else { return nil }
        let utf16 = text.utf16
        guard let start = utf16.index(utf16.startIndex, offsetBy: entity.offset, limitedBy: utf16.endIndex),
              let end = utf16.index(start, offsetBy: entity.length, limitedBy: utf16.endIndex),
              let lower = start.samePosition(in: text.unicodeScalars),
              let upper = end.samePosition(in: text.unicodeScalars)
        else { return nil }
        return lower..<upper
    }

    private static func apply(_ entity: Entity, text: String, to string: inout AttributedString,
                              in range: Range<AttributedString.Index>) {
        switch entity.type {
        case "bold":
            add(.stronglyEmphasized, to: &string, in: range)
        case "italic":
            add(.emphasized, to: &string, in: range)
        case "underline":
            string[range].underlineStyle = .single
        case "strikethrough":
            string[range].strikethroughStyle = .single
        case "code", "pre":
            add(.code, to: &string, in: range)
        case "url":
            if let url = link(text) { string[range].link = url }
        case "text_url":
            if let url = entity.url.flatMap(link) { string[range].link = url }
        case "email":
            if let url = URL(string: "mailto:\(text)"), !text.contains(where: \.isWhitespace) { string[range].link = url }
        case "mention", "mention_name", "hashtag", "cashtag", "bot_command":
            string[range].foregroundColor = .accentColor
        default:
            // custom_emoji keeps its ordinary emoji; spoiler, blockquote and the rest read as plain text.
            break
        }
    }

    /// Adds an inline intent without dropping the ones already on the span (bold inside italic stays both).
    private static func add(_ intent: InlinePresentationIntent, to string: inout AttributedString,
                            in range: Range<AttributedString.Index>) {
        for run in string[range].runs {
            let current = run.inlinePresentationIntent ?? []
            string[run.range].inlinePresentationIntent = current.union(intent)
        }
    }

    /// A web or mail link; a bare host gets `https://`. Anything else is not a link.
    static func link(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let candidate = trimmed.contains("://") || trimmed.lowercased().hasPrefix("mailto:") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme)
        else { return nil }
        if scheme != "mailto" && (url.host() ?? "").isEmpty { return nil }
        return url
    }
}
