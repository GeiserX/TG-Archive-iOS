import SwiftUI

/// One chat in the list: avatar, title, the preview line and the relative date.
struct ChatRow: View {
    let chat: Chat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(chat: chat)
            VStack(alignment: .leading, spacing: 3) {
                if dynamicTypeSize.isAccessibilitySize {
                    title
                    date
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer(minLength: 8)
                        date
                    }
                }
                PreviewLabel(line: PreviewLine(chat.preview))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.row.\(chat.ref)")
    }

    private var title: some View {
        HStack(spacing: 4) {
            if chat.isForum {
                Image(systemName: "number")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("chats.forum"))
            }
            Text(chat.displayTitle)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
        }
    }

    @ViewBuilder
    private var date: some View {
        if let date = chat.preview?.date {
            Text(RelativeDate.string(for: date))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// The preview line: the sender in the primary colour, then the kind's glyph, then the text.
struct PreviewLabel: View {
    let line: PreviewLine?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let line {
                composed(line)
            } else {
                Text("chats.preview.empty")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
    }

    private func composed(_ line: PreviewLine) -> Text {
        let glyph = line.symbol.map { Text("\(Image(systemName: $0)) ") } ?? Text(verbatim: "")
        let body = Text(verbatim: line.text)
        if line.isService {
            return Text("\(glyph)\(body.italic())")
        }
        if let sender = line.sender {
            let name = Text(verbatim: sender).foregroundStyle(.primary)
            return Text("chats.preview.sender \(name) \(glyph)\(body)")
        }
        return Text("\(glyph)\(body)")
    }
}
