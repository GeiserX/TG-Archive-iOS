import SwiftUI

/// A thread: newest at the bottom, day headers, older pages as you scroll up. Opened at an anchor (a search
/// hit) it starts there, pages newer messages as you scroll down, and offers a way to the newest.
struct ChatView: View {
    let session: Session
    let title: String?
    @Environment(SessionStore.self) private var store: SessionStore?
    @Environment(ChatAvailability.self) private var availability: ChatAvailability?
    @Environment(\.dismiss) private var dismiss
    @State private var model: ChatThreadModel
    @State private var position = ScrollPosition(idType: Int.self)
    /// The thread shows where it should: at the bottom, or at the anchor. Newer pages wait for it.
    @State private var settled = false

    init(session: Session, ref: String, title: String?, topicID: Int? = nil, anchor: Int? = nil) {
        self.session = session
        self.title = title
        _model = State(initialValue: ChatThreadModel(client: session.client, ref: ref, topicID: topicID,
                                                     anchor: anchor))
    }

    private var context: ThreadContext {
        ThreadContext(ref: model.ref, noDownload: session.stored.noDownload)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if model.window.hasOlder {
                    pageSpinner
                        .task(id: model.window.messages.first?.id) { await loadOlder() }
                }
                ForEach(rows, id: \.message.id) { row in
                    MessageRow(message: row.message, context: context, showsDay: row.startsDay,
                               startsRun: row.startsRun, showsSenders: model.showsSenders, topicID: model.topicID,
                               isAnchor: row.message.id == model.anchor)
                }
                if model.window.hasNewer && settled {
                    pageSpinner
                        .task(id: model.window.messages.last?.id) { await model.loadNewer() }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .scrollTargetLayout()
        }
        // Bottom only for the first offset. A bottom anchor for size changes makes the lazy stack loop near
        // the top, where rows of other heights keep changing its estimated size; an older page is pinned to
        // the message that was on top instead (`loadOlder`).
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .scrollPosition($position)
        .overlay { emptyState }
        .overlay(alignment: .bottomTrailing) { jumpButton }
        .errorBanner(model.error, retry: { Task { await model.retry() } })
        .navigationTitle(Text(verbatim: title ?? model.chat?.displayTitle ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.sessionEnded = { [weak store] client in await store?.sessionEnded(client) }
            guard !model.loaded else { return }
            await model.open()
            // The first offset is set while the list is still empty, so place the first page explicitly.
            if let anchor = model.anchor, model.window.messages.contains(where: { $0.id == anchor }) {
                position.scrollTo(id: anchor, anchor: .center)
            } else if let last = model.window.messages.last?.id {
                position.scrollTo(id: last, anchor: .bottom)
                // Rows measured on the way down change the lazy stack's estimate; pin the newest once more.
                try? await Task.sleep(for: .milliseconds(150))
                position.scrollTo(id: last, anchor: .bottom)
            }
            settled = model.loaded
        }
        .onChange(of: model.isUnavailable) { _, gone in
            if gone { availability?.chatWentAway() }
        }
        .alert(Text("chat.unavailable"), isPresented: .constant(model.isUnavailable)) {
            Button("chat.unavailable.ok") { dismiss() }
        }
    }

    private struct Row {
        let message: Message
        let startsDay: Bool
        let startsRun: Bool
    }

    private var rows: [Row] {
        let window = model.window
        return window.messages.indices.map { index in
            Row(message: window.messages[index], startsDay: window.startsDay(at: index),
                startsRun: window.startsRun(at: index))
        }
    }

    private var pageSpinner: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    /// Loads the page above and keeps the message that was on top where it was.
    private func loadOlder() async {
        let top = model.window.messages.first?.id
        await model.loadOlder()
        if let top, model.window.messages.first?.id != top {
            position.scrollTo(id: top, anchor: .top)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !model.loaded && model.error == nil && !model.isUnavailable {
            ProgressView()
        } else if model.loaded && model.window.messages.isEmpty {
            ContentUnavailableView("chat.empty", systemImage: "text.bubble")
        }
    }

    @ViewBuilder
    private var jumpButton: some View {
        if model.window.hasNewer && model.loaded {
            Button {
                Task {
                    await model.jumpToLatest()
                    if let last = model.window.messages.last?.id { position.scrollTo(id: last, anchor: .bottom) }
                }
            } label: {
                Label("chat.jumpToLatest", systemImage: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding()
            .accessibilityIdentifier("chat.jumpToLatest")
        }
    }
}

/// Tells the chat list that a thread found its chat gone (a 404), so the list asks the server again.
@MainActor @Observable
final class ChatAvailability {
    /// Bumped each time a thread finds its chat gone.
    private(set) var generation = 0

    func chatWentAway() { generation += 1 }
}
