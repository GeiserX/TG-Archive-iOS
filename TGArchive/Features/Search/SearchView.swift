import SwiftUI

/// The Search tab: every message the login sees, searched on the server, in its own navigation stack.
/// A hit opens its chat at the message.
struct SearchView: View {
    let session: Session

    var body: some View {
        NavigationStack {
            SearchScreen(session: session)
                .chatRoutes(session: session)
        }
    }
}

struct SearchScreen: View {
    let session: Session
    @Environment(SessionStore.self) private var store: SessionStore?
    @State private var model: SearchModel
    @State private var text = ""

    init(session: Session) {
        self.session = session
        _model = State(initialValue: SearchModel(client: session.client))
    }

    var body: some View {
        List {
            if let error = model.error {
                Section {
                    ErrorRow(error: error) { await model.retry() }
                }
            }
            ForEach(model.results, id: \.key) { hit in
                NavigationLink(value: hit.route) {
                    SearchRow(hit: hit, query: model.appliedQuery ?? "")
                }
            }
            if model.canLoadMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .task(id: model.results.count) { await model.loadMore() }
            }
            if model.reachedOffsetLimit {
                Text("search.limit")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .listRowSeparator(.hidden)
                    .accessibilityIdentifier("search.limit")
            }
        }
        .listStyle(.plain)
        .overlay { emptyState }
        .navigationTitle(Text("tab.search"))
        .searchable(text: $text, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("search.prompt"))
        .autocorrectionDisabled()
        .errorBanner(model.indexed ? nil : String(localized: "search.notIndexed"))
        .task(id: text) {
            model.sessionEnded = { [weak store] client in await store?.sessionEnded(client) }
            await model.search(text)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.results.isEmpty && model.error == nil {
            if model.isLoading {
                ProgressView()
            } else if let query = model.appliedQuery {
                if model.indexed { ContentUnavailableView.search(text: query) }
            } else if text.nonBlank == nil {
                ContentUnavailableView {
                    Label("search.start.title", systemImage: "magnifyingglass")
                } description: {
                    Text("search.start.description")
                }
            }
        }
    }
}

/// One hit: the chat's avatar and title, the date, the sender (and the topic in a forum), and the matched
/// words marked in the text.
struct SearchRow: View {
    let hit: SearchResult
    let query: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(endpoint: hit.chat.avatarURL == nil ? nil : .avatar(ref: hit.chat.ref),
                       title: hit.chat.displayTitle, seed: hit.chat.ref)
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
                byline
                snippet
                if hit.isDeleted {
                    Label("chat.deleted", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("search.row.\(hit.chat.ref).\(hit.id)")
    }

    private var title: some View {
        Text(hit.chat.displayTitle)
            .font(.headline)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    private var date: some View {
        Text(RelativeDate.string(for: hit.date))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// The sender, and the topic for a forum hit.
    @ViewBuilder
    private var byline: some View {
        let sender = hit.senderName?.nonBlank
        let topic = hit.topicTitle?.nonBlank
        if sender != nil || topic != nil {
            HStack(spacing: 6) {
                if let sender {
                    Text(verbatim: sender)
                        .foregroundStyle(.primary)
                }
                if let topic {
                    HStack(spacing: 2) {
                        Image(systemName: "number")
                            .accessibilityHidden(true)
                        Text(verbatim: topic)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .lineLimit(1)
        }
    }

    /// The text with the matched words marked. A hit found only in a voice message's transcript says so,
    /// since the transcript itself is not part of the hit.
    @ViewBuilder
    private var snippet: some View {
        let text = hit.text?.nonBlank
        if let text {
            Text(Self.attributed(SearchSnippet(text, query: query)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 3)
        }
        if hit.matchedIn == "transcript" {
            Label("search.matchedTranscript", systemImage: "waveform")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if text == nil {
            Label("search.noText", systemImage: "text.bubble")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// The snippet with every matched word in bold, in the primary colour, on a tint of the accent colour.
    static func attributed(_ snippet: SearchSnippet) -> AttributedString {
        var result = AttributedString(snippet.text)
        for mark in snippet.marks {
            guard let lower = AttributedString.Index(mark.lowerBound, within: result),
                  let upper = AttributedString.Index(mark.upperBound, within: result) else { continue }
            result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
            result[lower..<upper].foregroundColor = .primary
            result[lower..<upper].backgroundColor = Color.accentColor.opacity(0.25)
        }
        return result
    }
}
