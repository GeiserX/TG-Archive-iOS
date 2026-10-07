import SwiftUI

/// The Chats tab: the chat list in its own navigation stack.
struct ChatListView: View {
    let session: Session

    var body: some View {
        NavigationStack {
            ChatListScreen(session: session, archived: false)
                .chatRoutes(session: session)
        }
    }
}

extension View {
    /// Where every `Route` leads. The Search tab's stack uses it too.
    func chatRoutes(session: Session) -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .archived:
                ChatListScreen(session: session, archived: true)
            case let .topics(ref, title):
                TopicListView(session: session, ref: ref, title: title)
            case let .chat(_, title, _, _):
                ChatPlaceholderView(title: title)
            }
        }
    }
}

/// The list itself, for every chat or for the archived ones.
struct ChatListScreen: View {
    let session: Session
    let archived: Bool
    @Environment(SessionStore.self) private var store: SessionStore?
    @State private var model: ChatListModel
    @State private var search = ""
    @State private var folderID: Int?

    init(session: Session, archived: Bool) {
        self.session = session
        self.archived = archived
        _model = State(initialValue: ChatListModel(client: session.client, archived: archived))
    }

    private var query: ChatListModel.Query { .init(search: search, folderID: folderID) }

    var body: some View {
        List {
            if let error = model.error {
                Section {
                    ErrorRow(error: error) { await model.retry() }
                }
            }
            if showsArchivedRow {
                NavigationLink(value: Route.archived) {
                    Label {
                        Text("chats.archived \(model.archivedCount)")
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                }
                .accessibilityIdentifier("chats.archived")
            }
            ForEach(model.chats) { chat in
                NavigationLink(value: route(for: chat)) {
                    ChatRow(chat: chat)
                }
            }
            if model.hasMore && model.error == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
                    .task(id: model.chats.count) { await model.loadMore() }
            }
        }
        .listStyle(.plain)
        .overlay { emptyState }
        .navigationTitle(archived ? Text("chats.archived.title") : Text("chats.title"))
        .searchable(text: $search, prompt: Text("chats.search.prompt"))
        .toolbar {
            if !archived && !model.folders.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { folderMenu }
            }
        }
        .refreshable { await model.refresh() }
        .task(id: query) {
            model.sessionEnded = { [weak store] client in await store?.sessionEnded(client) }
            // Typing waits for a pause; the first load and a folder change do not.
            if let applied = model.appliedQuery, applied.search != (search.nonBlank ?? "") {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
            }
            await model.open(query)
        }
    }

    private var showsArchivedRow: Bool {
        !archived && model.archivedCount > 0 && model.appliedQuery == ChatListModel.Query()
            && search.nonBlank == nil && folderID == nil
    }

    private func route(for chat: Chat) -> Route {
        chat.isForum
            ? .topics(ref: chat.ref, title: chat.displayTitle)
            : .chat(ref: chat.ref, title: chat.displayTitle)
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.chats.isEmpty && model.error == nil && !model.isLoading && model.appliedQuery != nil
            && !showsArchivedRow {
            if let text = model.appliedQuery?.search.nonBlank {
                ContentUnavailableView.search(text: text)
            } else {
                ContentUnavailableView(archived ? "chats.archived.empty" : "chats.empty",
                                       systemImage: "bubble.left.and.bubble.right")
            }
        } else if model.chats.isEmpty && model.isLoading && !showsArchivedRow {
            ProgressView()
        }
    }

    private var folderMenu: some View {
        Menu {
            Picker(selection: $folderID) {
                Text("chats.folder.all").tag(Int?.none)
                ForEach(model.folders) { folder in
                    Text(verbatim: [folder.emoticon, folder.title].compactMap(\.self).joined(separator: " "))
                        .tag(Int?.some(folder.id))
                }
            } label: {
                Text("chats.folders")
            }
        } label: {
            Label("chats.folders", systemImage: folderID == nil
                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("chats.folders")
    }
}

/// An error inside a list, with Retry. Only `.unauthorized` leaves the screen, and it never gets here.
struct ErrorRow: View {
    let error: APIError
    let retry: () async -> Void
    @State private var retrying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Button("list.retry") {
                retrying = true
                Task {
                    await retry()
                    retrying = false
                }
            }
            .disabled(retrying)
        }
        .padding(.vertical, 4)
    }
}

/// Stands in for the thread until the thread screen exists.
struct ChatPlaceholderView: View {
    let title: String?

    var body: some View {
        ContentUnavailableView("chat.placeholder", systemImage: "text.bubble")
            .navigationTitle(title.map { Text(verbatim: $0) } ?? Text(verbatim: ""))
            .navigationBarTitleDisplayMode(.inline)
    }
}
