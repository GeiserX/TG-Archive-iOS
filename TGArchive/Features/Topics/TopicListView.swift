import SwiftUI

/// A forum chat's topics. Tapping one opens the thread filtered to it.
struct TopicListView: View {
    let session: Session
    let title: String
    @Environment(SessionStore.self) private var store: SessionStore?
    @State private var model: TopicListModel

    init(session: Session, ref: String, title: String) {
        self.session = session
        self.title = title
        _model = State(initialValue: TopicListModel(client: session.client, ref: ref))
    }

    var body: some View {
        List {
            if let error = model.error {
                Section {
                    ErrorRow(error: error) { await model.load() }
                }
            }
            ForEach(model.topics) { topic in
                NavigationLink(value: Route.chat(ref: model.ref, title: TopicRow.title(of: topic), topicID: topic.id)) {
                    TopicRow(topic: topic)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if model.topics.isEmpty && model.error == nil {
                if model.loaded {
                    ContentUnavailableView("topics.empty", systemImage: "number")
                } else {
                    ProgressView()
                }
            }
        }
        .navigationTitle(Text(verbatim: title))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task {
            model.sessionEnded = { [weak store] client in await store?.sessionEnded(client) }
            await model.open()
        }
    }
}

/// A topic: its emoji or a glyph in its colour, the title, a lock when closed, a pin when pinned, the
/// message count and the date of its last message.
struct TopicRow: View {
    let topic: Topic
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static func title(of topic: Topic) -> String {
        topic.title?.nonBlank ?? String(localized: "topics.untitled")
    }

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: iconSize, height: iconSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: Self.title(of: topic))
                        .font(.headline)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    if topic.isClosed {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("topics.closed"))
                    }
                    if topic.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(Text("topics.pinned"))
                    }
                    Spacer(minLength: 8)
                    if let date = topic.lastMessageDate {
                        Text(RelativeDate.string(for: date))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let count = topic.messageCount {
                    Text("topics.messageCount \(count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("topic.row.\(topic.id)")
    }

    @ViewBuilder
    private var icon: some View {
        if let emoji = topic.iconEmoji?.nonBlank {
            Text(verbatim: emoji)
                .font(.system(size: iconSize * 0.7))
                .minimumScaleFactor(0.5)
        } else {
            Image(systemName: "number.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Self.color(topic.iconColor))
        }
    }

    /// The topic's RGB colour, or the accent colour when it has none.
    static func color(_ rgb: Int?) -> Color {
        guard let rgb, (0...0xFFFFFF).contains(rgb) else { return .accentColor }
        return Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                     blue: Double(rgb & 0xFF) / 255)
    }
}
