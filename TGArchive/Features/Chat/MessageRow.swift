import SwiftUI

/// One message in the thread, with the day header above it when it opens a day. A service row is a centred
/// capsule; any other message is a bubble, ours on the right in the accent colour, theirs on the left.
struct MessageRow: View {
    let message: Message
    let context: ThreadContext
    let showsDay: Bool
    /// The first of a sender's run: the run's top gets a little room above it.
    let startsRun: Bool
    /// In a group: the sender's name and avatar go on the first message of a run.
    let showsSenders: Bool
    /// The thread's forum topic, whose root every message points at without quoting it.
    let topicID: Int?
    /// The message a search opened the thread at.
    let isAnchor: Bool

    var body: some View {
        VStack(spacing: 6) {
            if showsDay {
                DayHeader(date: message.date)
                    .padding(.vertical, 6)
            }
            if message.isService {
                ServiceCapsule(message: message)
                    .padding(.vertical, 2)
            } else {
                bubbleRow
            }
        }
        .padding(.top, startsRun && !showsDay ? 6 : 0)
    }

    private var hasAvatarColumn: Bool { showsSenders && !message.isOutgoing }

    private var bubbleRow: some View {
        HStack(alignment: .top, spacing: 6) {
            if message.isOutgoing { Spacer(minLength: 40) }
            if hasAvatarColumn {
                if startsRun {
                    SenderAvatar(message: message, ref: context.ref)
                } else {
                    SenderAvatar.spacer
                }
            }
            MessageBubble(message: message, context: context, showsSender: hasAvatarColumn && startsRun,
                          topicID: topicID, isAnchor: isAnchor)
            if !message.isOutgoing { Spacer(minLength: 40) }
        }
    }
}

/// The bubble: sender, forward line, reply quote, media, text, the marks the archive keeps, the time and the
/// reactions. A sticker or a round video with nothing around it goes without a bubble.
struct MessageBubble: View {
    let message: Message
    let context: ThreadContext
    let showsSender: Bool
    let topicID: Int?
    let isAnchor: Bool

    private var content: MessageContent { MessageContent(message) }
    private var reply: ReplyQuote? { ReplyQuote(message, topicID: topicID) }
    private var forwardedFrom: String? { message.rawData?.forwardFromName?.nonBlank }
    private var text: String? { message.text?.nonBlank == nil ? nil : message.text }

    private var isBare: Bool {
        guard text == nil, reply == nil, forwardedFrom == nil, !showsSender else { return false }
        switch content {
        case .sticker, .videoNote: return true
        default: return false
        }
    }

    var body: some View {
        VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
            if isBare {
                cell
                MessageFooter(message: message)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
                reactions
            } else {
                bubble
            }
        }
        .opacity(message.isDeleted ? 0.62 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("message.\(message.id)")
    }

    private var bubble: some View {
        BubbleLayout(spacing: 6, maxWidth: 520) {
            if showsSender, let name = message.senderDisplayName {
                Text(verbatim: name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AvatarView.color(for: SenderAvatar.seed(of: message)))
                    .lineLimit(1)
            }
            if let forwardedFrom {
                Label {
                    Text("chat.forwardedFrom \(forwardedFrom)")
                } icon: {
                    Image(systemName: "arrowshape.turn.up.right.fill")
                }
                .font(.caption.italic())
                .foregroundStyle(.secondary)
            }
            if let reply {
                ReplyQuoteView(quote: reply)
            }
            cell
            if let text {
                Text(EntityText.attributed(text, entities: message.rawData?.entities))
                    .font(.body)
                    .foregroundStyle(message.isDeleted ? .secondary : .primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            reactions
            MessageFooter(message: message)
                .layoutValue(key: BubbleLayout.Trailing.self, value: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if isAnchor {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
    }

    private var background: AnyShapeStyle {
        message.isOutgoing ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.fill.tertiary)
    }

    @ViewBuilder
    private var cell: some View {
        switch content {
        case .none:
            EmptyView()
        case let .photo(media):
            PhotoCell(message: message, media: media, context: context)
        case let .video(media):
            VideoCell(message: message, media: media, context: context)
        case let .videoNote(media):
            VideoNoteCell(message: message, media: media, context: context)
        case let .voice(media), let .audio(media):
            VoiceCell(message: message, media: media, context: context)
        case let .document(media):
            DocumentCell(message: message, media: media, context: context)
        case let .sticker(sticker):
            StickerCell(content: sticker, context: context)
        case let .location(location):
            LocationCell(content: location, context: context)
        case let .contact(contact):
            ContactCell(contact: contact)
        case let .poll(poll):
            PollCell(poll: poll)
        case let .unsupported(kind):
            MediaPlaceholder(unsupported: kind)
                .frame(width: MediaFrame.width)
        }
    }

    @ViewBuilder
    private var reactions: some View {
        let summary = ReactionSummary(reactions: message.reactions, removed: message.removedReactions)
        if !summary.isEmpty {
            ReactionChips(summary: summary)
        }
    }
}

/// The marks under a message: deleted in Telegram, pinned, edited, and the time.
struct MessageFooter: View {
    let message: Message

    var body: some View {
        HStack(spacing: 4) {
            if message.isDeleted {
                Image(systemName: "trash")
                    .accessibilityHidden(true)
                Text("chat.deleted")
            }
            if message.isPinned {
                Image(systemName: "pin.fill")
                    .accessibilityLabel(Text("chat.pinned"))
            }
            if message.isEdited {
                Text("chat.edited")
            }
            Text(message.date, format: .dateTime.hour().minute())
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}

/// The quote of the message a reply answers.
struct ReplyQuoteView: View {
    let quote: ReplyQuote

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.accentColor)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if let sender = quote.sender {
                    Text(verbatim: sender)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text(verbatim: quote.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .padding(.trailing, 8)
        .frame(maxWidth: MediaFrame.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("chat.replyTo \(quote.sender ?? "") \(quote.text)"))
    }
}

/// One chip per live reaction, then the reactions taken back folded into one muted chip.
struct ReactionChips: View {
    let summary: ReactionSummary

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(summary.chips) { chip in
                HStack(spacing: 3) {
                    if let emoji = chip.emoji {
                        Text(verbatim: emoji)
                    } else {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.tint)
                            .accessibilityLabel(Text("chat.reaction.custom"))
                    }
                    Text(chip.count, format: .number)
                        .monospacedDigit()
                }
                .font(.caption)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.background.opacity(0.7), in: Capsule())
                .accessibilityElement(children: .combine)
            }
            if summary.takenBack > 0 {
                Text("chat.reactions.takenBack \(summary.takenBack)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(.quaternary))
            }
        }
    }
}

/// A centred grey capsule for a chat event: the sentence the archive stored, else one worded from the
/// action with the server's table, else the glyph alone.
struct ServiceCapsule: View {
    let message: Message

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: ServiceText.symbol)
                .accessibilityHidden(message.serviceSentence != nil)
                .accessibilityLabel(Text("chat.service"))
            if let sentence = message.serviceSentence {
                Text(verbatim: sentence)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.fill.tertiary, in: Capsule())
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("message.\(message.id)")
    }
}

/// The day a run of messages was sent: Today, Yesterday, else the date.
struct DayHeader: View {
    let date: Date

    static func title(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "chat.day.today") }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "date.yesterday")
        }
        let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.wide).day().month(.wide)
        return calendar.component(.year, from: date) == calendar.component(.year, from: now)
            ? date.formatted(style)
            : date.formatted(style.year())
    }

    var body: some View {
        Text(verbatim: Self.title(for: date))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .frame(maxWidth: .infinity)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A small round avatar beside the first message of a sender's run in a group.
struct SenderAvatar: View {
    let message: Message
    let ref: String
    @Environment(\.displayScale) private var displayScale

    static let size: CGFloat = 32

    static var spacer: some View {
        Color.clear.frame(width: size, height: 1)
    }

    static func seed(of message: Message) -> String {
        message.senderID.map(String.init) ?? message.senderDisplayName ?? ""
    }

    var body: some View {
        Group {
            if message.senderAvatarURL != nil {
                RemoteImage(endpoint: .senderAvatar(ref: ref, messageID: message.id),
                            maxPixelSize: Int((Self.size * displayScale).rounded(.up))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: Self.size, height: Self.size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Circle()
            .fill(AvatarView.color(for: Self.seed(of: message)).gradient)
            .overlay {
                Text(verbatim: AvatarView.initials(of: message.senderDisplayName ?? ""))
                    .font(.system(size: Self.size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
    }
}

/// Lays chips out in rows, wrapping to the next row when one does not fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// The inside of a bubble: a column as wide as its widest part, never wider than the room it is offered or
/// `maxWidth`, so short messages get short bubbles and long ones wrap. The footer sits at the trailing edge.
struct BubbleLayout: Layout {
    struct Trailing: LayoutValueKey {
        static let defaultValue = false
    }

    var spacing: CGFloat = 6
    var maxWidth: CGFloat = 520

    private func sizes(_ subviews: Subviews, proposal: ProposedViewSize) -> [CGSize] {
        let width = min(proposal.width ?? maxWidth, maxWidth)
        return subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = sizes(subviews, proposal: proposal)
        let visible = sizes.filter { $0.height > 0 }
        let width = sizes.map(\.width).max() ?? 0
        let height = visible.map(\.height).reduce(0, +) + spacing * CGFloat(max(visible.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = sizes(subviews, proposal: proposal)
        var y = bounds.minY
        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            guard size.height > 0 else { continue }
            let x = subview[Trailing.self] ? bounds.maxX - size.width : bounds.minX
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: size.width, height: size.height))
            y += size.height + spacing
        }
    }
}
