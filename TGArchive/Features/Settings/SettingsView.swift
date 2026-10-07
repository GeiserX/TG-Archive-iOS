import SwiftUI

/// The Settings tab: where the app is connected, as whom, the archive's figures, sign out and clear cache.
struct SettingsView: View {
    let session: Session

    @Environment(SessionStore.self) private var store
    @State private var model = SettingsModel()
    @State private var confirmingSignOut = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var stored: StoredSession { session.stored }
    private var isAnonymous: Bool { stored.role == .anonymous }
    /// An open server has no sign-in to return to, so its button reads Disconnect.
    private var signOutTitle: LocalizedStringKey {
        isAnonymous ? "settings.disconnect" : "settings.signOut"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent {
                        Text(verbatim: stored.server.host)
                            .accessibilityIdentifier("settings.server")
                    } label: {
                        Text("settings.server")
                    }
                    LabeledContent {
                        // At accessibility sizes the value wraps under its label, so it lines up on the left.
                        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing) {
                            if let name = SettingsModel.accountName(for: stored) {
                                Text(verbatim: name)
                            }
                            Text(SettingsModel.roleLabel(for: stored))
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("settings.signedInAs")
                    } label: {
                        Text("settings.signedInAs")
                    }
                    if stored.noDownload {
                        Label { Text("settings.noDownload") } icon: { Image(systemName: "arrow.down.circle.dotted") }
                            .accessibilityIdentifier("settings.noDownload")
                    }
                } header: {
                    Text("settings.section.connection")
                }

                if let stats = model.visibleStats {
                    archive(stats)
                }

                Section {
                    Button(action: clearCache) {
                        HStack {
                            Text("settings.clearCache")
                            Spacer()
                            if model.cacheCleared {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(Text("settings.clearCache.done"))
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.clearCache")
                } footer: {
                    Text("settings.clearCache.footer")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Text("settings.about")
                    }
                    .accessibilityIdentifier("settings.about")
                }

                Section {
                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        HStack {
                            Text(signOutTitle)
                            Spacer()
                            if model.isSigningOut {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(model.isSigningOut)
                    .accessibilityIdentifier("settings.signOut")
                }
            }
            .navigationTitle(Text("settings.title"))
            .errorBanner(model.error, retry: reload)
            .task { await model.load(session, store: store) }
            .refreshable { await model.load(session, store: store) }
            .confirmationDialog(
                Text(isAnonymous ? LocalizedStringKey("settings.disconnect.confirm.title") : LocalizedStringKey("settings.signOut.confirm.title")),
                isPresented: $confirmingSignOut,
                titleVisibility: .visible
            ) {
                Button(role: .destructive) {
                    Task { @MainActor in await model.signOut(using: store) }
                } label: {
                    Text(signOutTitle)
                }
                .accessibilityIdentifier("settings.signOut.confirm")
            } message: {
                Text(isAnonymous ? LocalizedStringKey("settings.disconnect.confirm.message") : LocalizedStringKey("settings.signOut.confirm.message"))
            }
        }
    }

    private func archive(_ stats: ArchiveStats) -> some View {
        Section {
            if let chats = stats.chats {
                LabeledContent { Text(chats, format: .number) } label: { Text("settings.stats.chats") }
            }
            if let messages = stats.messages {
                LabeledContent { Text(messages, format: .number) } label: { Text("settings.stats.messages") }
            }
            if let media = stats.mediaFiles {
                LabeledContent { Text(media, format: .number) } label: { Text("settings.stats.media") }
            }
            if let last = stats.lastBackupTime {
                LabeledContent {
                    Text(last, format: .dateTime.day().month().year().hour().minute())
                } label: {
                    Text("settings.stats.lastBackup")
                }
            }
        } header: {
            Text("settings.section.archive")
        }
        .accessibilityIdentifier("settings.archive")
    }

    private func reload() {
        Task { @MainActor in await model.load(session, store: store) }
    }

    private func clearCache() {
        Task { @MainActor in await model.clearCache(session, store: store) }
    }
}
