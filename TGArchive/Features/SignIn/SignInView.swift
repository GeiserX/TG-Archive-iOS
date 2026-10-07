import SwiftUI

/// Account or share link, for the server chosen on the connect screen.
struct SignInView: View {
    let server: ServerAddress
    let reason: EndReason?
    var onChangeServer: () -> Void

    @Environment(SessionStore.self) private var store
    @State private var model: SignInModel
    @FocusState private var focus: Field?

    private enum Field: Hashable { case username, password, token }

    init(server: ServerAddress, prefilledToken: String?, reason: EndReason?, username: String?,
         onChangeServer: @escaping () -> Void) {
        self.server = server
        self.reason = reason
        self.onChangeServer = onChangeServer
        _model = State(initialValue: SignInModel(prefilledToken: prefilledToken, username: username))
    }

    var body: some View {
        NavigationStack {
            Form {
                if let notice {
                    Section {
                        Label { Text(notice) } icon: { Image(systemName: "info.circle") }
                            .accessibilityIdentifier("signin.notice")
                    }
                }

                Section {
                    LabeledContent {
                        Text(verbatim: server.host)
                            .accessibilityIdentifier("signin.server")
                    } label: {
                        Text("signin.server")
                    }
                } footer: {
                    Text("signin.server.footer")
                }

                Section {
                    Picker(selection: $model.method) {
                        Text("signin.method.account").tag(SignInModel.Method.account)
                        Text("signin.method.link").tag(SignInModel.Method.shareLink)
                    } label: {
                        Text("signin.method")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("signin.method")
                }

                credentials

                Section {
                    Button(action: submit) {
                        HStack {
                            Text("signin.submit")
                            Spacer()
                            if store.isSigningIn {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!model.canSubmit || store.isSigningIn)
                    .accessibilityIdentifier("signin.submit")
                } footer: {
                    Text("signin.footer.oneSession")
                }
            }
            .navigationTitle(Text("signin.title"))
            .navigationBarTitleDisplayMode(.inline)
            .errorBanner(model.error?.message)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onChangeServer) { Text("signin.changeServer") }
                        .disabled(store.isSigningIn)
                        .accessibilityIdentifier("signin.changeServer")
                }
            }
        }
    }

    @ViewBuilder private var credentials: some View {
        switch model.method {
        case .account:
            Section {
                TextField(text: $model.username, prompt: Text("signin.username")) {
                    Text("signin.username")
                }
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.next)
                .focused($focus, equals: .username)
                .onSubmit { focus = .password }
                .accessibilityIdentifier("signin.username")

                SecureField(text: $model.password, prompt: Text("signin.password")) {
                    Text("signin.password")
                }
                .textContentType(.password)
                .submitLabel(.go)
                .focused($focus, equals: .password)
                .onSubmit(submit)
                .accessibilityIdentifier("signin.password")
            }
        case .shareLink:
            Section {
                TextField(text: $model.token, prompt: Text("signin.token.prompt"), axis: .vertical) {
                    Text("signin.token")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .lineLimit(1...4)
                .focused($focus, equals: .token)
                .accessibilityIdentifier("signin.token")
            } footer: {
                Text("signin.token.footer")
            }
        }
    }

    /// Why the user is here, when it is not their own choice.
    private var notice: String? {
        switch reason {
        case .expired: return String(localized: "signin.notice.expired")
        case .ended: return String(localized: "api.error.unauthorized")
        case nil:
            return store.lastSignOutWasLocalOnly ? String(localized: "signin.notice.localSignOut") : nil
        }
    }

    private func submit() {
        focus = nil
        Task { @MainActor in
            await model.submit(using: store)
        }
    }
}
