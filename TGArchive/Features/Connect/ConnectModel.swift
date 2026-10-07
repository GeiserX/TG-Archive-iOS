import Foundation
import Observation

/// The connect screen's state: the address being typed and the result of probing it.
@MainActor @Observable
final class ConnectModel {
    var address: String
    private(set) var isConnecting = false
    private(set) var error: SessionError?

    init(address: String = "") {
        self.address = address
    }

    var canConnect: Bool {
        !isConnecting && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The server answered that it has no login mode configured; the screen links the setup docs.
    var needsServerSetup: Bool { error == .setupRequired }

    /// Probes the address. True when the store moved on to sign-in or to the archive.
    @discardableResult
    func connect(using store: SessionStore) async -> Bool {
        guard canConnect else { return false }
        isConnecting = true
        error = nil
        defer { isConnecting = false }
        do {
            try await store.connect(address)
            return true
        } catch {
            self.error = error
            return false
        }
    }

    /// What `PasteButton` hands over: the first non-empty string becomes the address and is probed at once.
    /// A share link carries its token to the sign-in screen.
    @discardableResult
    func paste(_ strings: [String], using store: SessionStore) async -> Bool {
        let text = strings.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let text else { return false }
        address = text
        return await connect(using: store)
    }
}
