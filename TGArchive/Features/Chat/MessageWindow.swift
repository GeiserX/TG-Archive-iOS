import Foundation

/// The part of a thread the app holds: messages oldest first, and whether the server has more on either side.
///
/// The server answers newest first and orders a page by date, then id; ids are not a time order (an imported
/// message can be older than a message with a lower id). Every page is therefore merged by id, the newer copy
/// winning, and the whole window is kept sorted by date, then id.
struct MessageWindow: Equatable, Sendable {
    private(set) var messages: [Message] = []
    /// Older messages exist past the first one.
    private(set) var hasOlder = false
    /// Newer messages exist past the last one: only when the thread was opened at an anchor.
    private(set) var hasNewer = false

    init() {}

    /// The newest page of a thread. `full` is true when the page came back as long as asked, so more may exist.
    init(newest page: [Message], full: Bool) {
        merge(page)
        hasOlder = full
        hasNewer = false
    }

    /// The page that holds an anchor and the messages before it. Newer messages are assumed until a page
    /// of them comes back short.
    init(anchored page: [Message], full: Bool) {
        merge(page)
        hasOlder = full
        hasNewer = true
    }

    /// Adds an older page.
    mutating func addOlder(_ page: [Message], full: Bool) {
        merge(page)
        hasOlder = full
    }

    /// Adds a newer page.
    mutating func addNewer(_ page: [Message], full: Bool) {
        merge(page)
        hasNewer = full
    }

    /// The cursor for the page before the oldest message: its date and id, as the server pages.
    var olderCursor: MessageCursor? {
        messages.first.map { .before(date: $0.date, id: $0.id) }
    }

    /// The cursor for the page after the highest id held; the server's `after_id` bound is by id.
    var newerCursor: MessageCursor? {
        messages.map(\.id).max().map { .after(id: $0) }
    }

    /// Merges a page without duplicates: a message already held is replaced by the copy just read.
    mutating func merge(_ page: [Message]) {
        guard !page.isEmpty else { return }
        var byID: [Int: Message] = [:]
        for message in messages { byID[message.id] = message }
        for message in page { byID[message.id] = message }
        messages = byID.values.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
        }
    }

    /// True when the message at `index` is the first of its local day, so a day header goes above it.
    func startsDay(at index: Int, calendar: Calendar = .current) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0 else { return true }
        return !calendar.isDate(messages[index].date, inSameDayAs: messages[index - 1].date)
    }

    /// True when the message at `index` starts a run of one sender's messages: the sender's name and avatar
    /// go on it. A new day, a service row or another sender starts a run.
    func startsRun(at index: Int, calendar: Calendar = .current) -> Bool {
        guard messages.indices.contains(index) else { return false }
        guard index > 0, !startsDay(at: index, calendar: calendar) else { return true }
        let previous = messages[index - 1]
        let current = messages[index]
        if previous.isService || current.isService { return true }
        if previous.isOutgoing != current.isOutgoing { return true }
        return previous.senderKey != current.senderKey
    }
}

extension Message {
    /// A row the archive kept for a chat event: a join, a title change, a topic made.
    var isService: Bool {
        rawData?.serviceType != nil || rawData?.actionType != nil
    }

    /// The sender's name as the archive stored it, else the current first and last name.
    var senderDisplayName: String? {
        if let name = senderName?.nonBlank { return name }
        let name = [firstName?.nonBlank, lastName?.nonBlank].compactMap(\.self).joined(separator: " ")
        return name.isEmpty ? nil : name
    }

    /// A service row's sentence: the one the archive stored, else one worded from the action with the server's
    /// table and the sender's name, else nil (the capsule shows its glyph alone).
    var serviceSentence: String? {
        text?.nonBlank ?? ServiceText.sentence(action: rawData?.actionType, title: rawData?.newTitle,
                                               actor: senderDisplayName)
    }

    /// Who sent it, for grouping a run; channel posts have no sender id and group by name.
    fileprivate var senderKey: String {
        senderID.map(String.init) ?? senderDisplayName ?? ""
    }
}
