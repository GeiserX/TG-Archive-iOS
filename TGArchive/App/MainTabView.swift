import SwiftUI

/// The signed-in shell: Chats, Search and Settings. A new session gets a new shell, so no screen keeps
/// anything from the one before.
struct MainTabView: View {
    let session: Session

    @Environment(SessionStore.self) private var store
    /// The user closed the launch check's offline banner.
    @State private var problemDismissed = false

    var body: some View {
        TabView {
            Tab("tab.chats", systemImage: "bubble.left.and.bubble.right") {
                ChatListView(session: session)
            }
            Tab("tab.search", systemImage: "magnifyingglass") {
                TabPlaceholder(title: "tab.search", systemImage: "magnifyingglass")
            }
            Tab("tab.settings", systemImage: "gearshape") {
                SettingsView(session: session)
            }
        }
        .errorBanner(problemDismissed ? nil : store.connectionProblem, dismiss: { problemDismissed = true })
    }
}

/// Holds a tab's place until its screen exists.
private struct TabPlaceholder: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label { Text(title) } icon: { Image(systemName: systemImage) }
            } description: {
                Text("tab.placeholder")
            }
            .navigationTitle(Text(title))
        }
    }
}
