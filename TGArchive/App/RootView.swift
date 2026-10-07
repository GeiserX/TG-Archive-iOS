import SwiftUI

/// Picks the screen for the session phase: connect, sign in, or the archive. It owns the one `SessionStore`
/// and hands it to every screen through the environment.
struct RootView: View {
    @State private var store = SessionStore()
    /// The user tapped "Other server" on the sign-in screen.
    @State private var changingServer = false

    var body: some View {
        content
            .environment(store)
            .task { await store.restore() }
            .onChange(of: store.phase) { changingServer = false }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .restoring:
            ProgressView()
                .accessibilityIdentifier("root.restoring")
        case .connect:
            ConnectView(initialAddress: store.lastServer ?? "")
        case let .signIn(server, prefilledToken, reason):
            if changingServer {
                ConnectView(initialAddress: server.baseURL.absoluteString,
                            onCancel: { changingServer = false },
                            onConnected: { changingServer = false })
            } else {
                SignInView(server: server, prefilledToken: prefilledToken, reason: reason,
                           username: store.lastUsername, onChangeServer: { changingServer = true })
                    .id(SignInIdentity(server: server, token: prefilledToken, reason: reason))
            }
        case let .ready(session):
            MainTabView(session: session)
                .id(ObjectIdentifier(session.client))
        }
    }
}

/// A new server, link or reason starts the sign-in screen afresh.
private struct SignInIdentity: Hashable {
    let server: ServerAddress
    let token: String?
    let reason: EndReason?
}

#Preview {
    RootView()
}
