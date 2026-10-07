import Foundation
import Observation

/// The sign-in screen's state: an account login or a share link, and what the last attempt said.
@MainActor @Observable
final class SignInModel {
    enum Method: Hashable, Sendable {
        case account
        case shareLink
    }

    var method: Method
    var username: String
    var password = ""
    /// A share link or a bare token, as typed or pasted.
    var token: String
    private(set) var error: SessionError?
    /// After a 429 the button stays off for a minute. Nothing is ever retried on its own.
    private(set) var isLockedOut = false

    @ObservationIgnored private let lockout: Duration
    @ObservationIgnored private var unlock: Task<Void, Never>?

    init(prefilledToken: String?, username: String?, lockout: Duration = .seconds(60)) {
        method = prefilledToken == nil ? .account : .shareLink
        token = prefilledToken ?? ""
        self.username = username ?? ""
        self.lockout = lockout
    }

    /// The token to send: the `#token=` part of a pasted link, otherwise the text as typed. Its format is never
    /// checked; the server only needs a non-empty string.
    var tokenValue: String? {
        let text = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("#token="), let linked = ServerAddress.parse(text)?.token {
            return linked
        }
        return text
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSubmit: Bool {
        guard !isLockedOut else { return false }
        switch method {
        case .account: return !trimmedUsername.isEmpty && !password.isEmpty
        case .shareLink: return tokenValue != nil
        }
    }

    /// One attempt, only when the user asks. The store refuses a second one while the first is in flight.
    func submit(using store: SessionStore) async {
        guard canSubmit, !store.isSigningIn else { return }
        error = nil
        do {
            switch method {
            case .account:
                try await store.signIn(username: trimmedUsername, password: password)
            case .shareLink:
                guard let tokenValue else { return }
                try await store.signIn(token: tokenValue)
            }
            password = ""
        } catch {
            self.error = error
            if error == .api(.rateLimited) { lockOut() }
        }
    }

    private func lockOut() {
        isLockedOut = true
        unlock?.cancel()
        unlock = Task { [weak self, lockout] in
            try? await Task.sleep(for: lockout)
            guard !Task.isCancelled else { return }
            self?.isLockedOut = false
        }
    }
}
