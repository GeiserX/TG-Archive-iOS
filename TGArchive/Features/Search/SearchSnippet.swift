import Foundation

/// A search hit's text as the result row shows it: one line of whitespace, a window around the first
/// matched word, and every matched word marked. A word matches when it starts with one of the query's words,
/// ignoring case and diacritics, which is the word-prefix rule the server searched with: "solder" marks
/// "soldering", "cafe" marks "café", "old" marks nothing in "soldering".
struct SearchSnippet: Equatable, Sendable {
    /// The longest snippet, in characters.
    static let window = 180
    /// A match further in than this moves the window so the match shows with some text before it.
    static let lead = 60
    /// How much text the moved window keeps before the match.
    static let context = 40

    let text: String
    /// The marked words, in order, as ranges of `text`.
    let marks: [Range<String.Index>]

    var markedWords: [String] { marks.map { String(text[$0]) } }

    init(text: String, marks: [Range<String.Index>]) {
        self.text = text
        self.marks = marks
    }

    init(_ source: String, query: String) {
        let flat = source.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let terms = Self.terms(in: query)
        let first = Self.matches(in: flat, terms: terms).first
        var start = flat.startIndex
        if let first, flat.distance(from: flat.startIndex, to: first.lowerBound) > Self.lead {
            start = flat.index(first.lowerBound, offsetBy: -Self.context)
        }
        let end = flat.index(start, offsetBy: Self.window, limitedBy: flat.endIndex) ?? flat.endIndex
        let body = String(flat[start..<end])
        let prefix = start > flat.startIndex ? "…" : ""
        let suffix = end < flat.endIndex ? "…" : ""
        let text = prefix + body + suffix
        // Matched again on the snippet itself, so a word cut by the window's edge is marked as it shows.
        self.init(text: text, marks: Self.matches(in: text, terms: terms))
    }

    /// The query's words, folded: runs of letters and digits, so "foo_bar" and "covid-19" are two words each,
    /// as the server's index splits them.
    static func terms(in query: String) -> [String] {
        words(in: query).map { fold(query[$0]) }
    }

    /// The words of `text` that start with one of `terms`.
    static func matches(in text: String, terms: [String]) -> [Range<String.Index>] {
        guard !terms.isEmpty else { return [] }
        return words(in: text).filter { range in
            let word = fold(text[range])
            return terms.contains { word.hasPrefix($0) }
        }
    }

    private static func words(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character.isLetter || character.isNumber {
                if start == nil { start = index }
            } else if let open = start {
                ranges.append(open..<index)
                start = nil
            }
            index = text.index(after: index)
        }
        if let open = start { ranges.append(open..<text.endIndex) }
        return ranges
    }

    private static func fold(_ text: Substring) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
