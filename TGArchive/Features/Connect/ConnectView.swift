import SwiftUI

/// First run and after a sign-out from an open server: the server address, or a pasted share link.
struct ConnectView: View {
    /// Set when the user came here from sign-in to change server; shows a Cancel button.
    var onCancel: (() -> Void)?
    /// Called once the store has moved on.
    var onConnected: (() -> Void)?

    @Environment(SessionStore.self) private var store
    @State private var model: ConnectModel
    @FocusState private var addressFocused: Bool

    static let serverDocs = URL(string: "https://github.com/GeiserX/Telegram-Archive")!
    static let accessDocs = URL(string: "https://github.com/GeiserX/Telegram-Archive/blob/main/docs/viewer/access.md")!

    init(initialAddress: String = "", onCancel: (() -> Void)? = nil, onConnected: (() -> Void)? = nil) {
        _model = State(initialValue: ConnectModel(address: initialAddress))
        self.onCancel = onCancel
        self.onConnected = onConnected
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                addressSection
                actionsSection
                if model.needsServerSetup {
                    Section {
                        Link(destination: Self.accessDocs) {
                            Label { Text("connect.setup.docs") } icon: { Image(systemName: "book") }
                        }
                    }
                }
            }
            .errorBanner(errorMessage, retry: retry)
            .toolbar {
                if let onCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onCancel) { Text("common.cancel") }
                            .accessibilityIdentifier("connect.cancel")
                    }
                }
            }
        }
    }

    private var errorMessage: String? { model.error?.message }

    /// Retrying makes sense for a failed probe, not for a server that needs setting up first.
    private var retry: (() -> Void)? {
        guard model.error != nil, !model.needsServerSetup else { return nil }
        return { connect() }
    }

    private var addressSection: some View {
        Section {
            TextField(text: $model.address, prompt: Text("connect.address.prompt")) {
                Text("connect.address.label")
            }
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($addressFocused)
            .onSubmit { connect() }
            .accessibilityIdentifier("connect.address")
        } header: {
            Text("connect.address.label")
        } footer: {
            Text("connect.address.footer")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                connect()
            } label: {
                HStack {
                    Text("connect.continue")
                    Spacer()
                    if model.isConnecting {
                        ProgressView()
                    }
                }
            }
            .disabled(!model.canConnect)
            .accessibilityIdentifier("connect.continue")

            LabeledContent {
                PasteButton(payloadType: String.self) { strings in
                    paste(strings)
                }
                .labelStyle(.titleAndIcon)
                .buttonBorderShape(.capsule)
                .disabled(model.isConnecting)
                .accessibilityIdentifier("connect.paste")
            } label: {
                Text("connect.paste.label")
            }
        } footer: {
            Text("connect.paste.footer")
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("app.name")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("root.title")
            Text("connect.intro")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: Self.serverDocs) {
                Text("connect.docs")
            }
            .font(.body)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func paste(_ strings: [String]) {
        addressFocused = false
        Task { @MainActor in
            if await model.paste(strings, using: store) { onConnected?() }
        }
    }

    private func connect() {
        addressFocused = false
        Task { @MainActor in
            if await model.connect(using: store) { onConnected?() }
        }
    }
}

#Preview {
    ConnectView()
        .environment(SessionStore())
}
