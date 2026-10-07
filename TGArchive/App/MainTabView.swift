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
                SearchView(session: session)
            }
            Tab("tab.settings", systemImage: "gearshape") {
                SettingsView(session: session)
            }
        }
        .errorBanner(problemDismissed ? nil : store.connectionProblem, dismiss: { problemDismissed = true })
    }
}
