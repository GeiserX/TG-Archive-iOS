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
        .safeAreaInset(edge: .top, spacing: 0) {
            if session.isDemo { demoBanner }
        }
    }

    /// Says on every screen that this is the bundled demo, not someone's archive, with the way out.
    private var demoBanner: some View {
        HStack(spacing: 8) {
            Label { Text("demo.banner") } icon: { Image(systemName: "sparkles") }
                .accessibilityIdentifier("demo.banner")
            Spacer(minLength: 8)
            Button {
                Task { @MainActor in await store.signOut() }
            } label: {
                Text("demo.exit").bold()
            }
            .accessibilityIdentifier("demo.exit")
        }
        .font(.footnote)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.tint.opacity(0.15))
    }
}
