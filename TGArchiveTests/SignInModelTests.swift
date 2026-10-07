import Foundation
import Testing
@testable import TGArchive

@MainActor
@Suite("Sign-in screen")
struct SignInModelTests {
    private let vault = MemoryVault()

    /// A store showing sign-in for `server`, the way the connect screen leaves it.
    private func signInStore(_ server: MockServer) async throws -> SessionStore {
        let store = FakeArchive.store(vault: vault)
        try await store.connect(server.address.baseURL.absoluteString)
        return store
    }

    @Test("The token sent is the link's #token= part, or the text as typed; its format is never checked",
          arguments: [
              ("https://archive.example.com/#token=demo-share-link-not-a-secret", "demo-share-link-not-a-secret"),
              ("https://archive.example.com/prefix/#token=abc&x=1", "abc"),
              ("  demo-share-link-not-a-secret \n", "demo-share-link-not-a-secret"),
              ("0f3c9a", "0f3c9a"),
              ("not hex, with spaces", "not hex, with spaces"),
              ("#token=", "#token="),
          ])
    func tokenValue(_ typed: String, _ sent: String) {
        let model = SignInModel(prefilledToken: nil, username: nil)
        model.token = typed
        #expect(model.tokenValue == sent)
    }

    @Test("An empty token, username or password cannot be sent")
    func canSubmit() {
        let model = SignInModel(prefilledToken: nil, username: "  ")
        #expect(model.method == .account)
        model.password = "pw"
        #expect(!model.canSubmit)
        model.username = "family"
        #expect(model.canSubmit)
        model.password = ""
        #expect(!model.canSubmit)

        model.method = .shareLink
        model.token = " \n"
        #expect(model.tokenValue == nil)
        #expect(!model.canSubmit)
    }

    @Test("A pasted link opens on Share link with the token filled in; otherwise Account with the last username")
    func defaults() {
        let link = SignInModel(prefilledToken: "demo-share-link-not-a-secret", username: "family")
        #expect(link.method == .shareLink)
        #expect(link.token == "demo-share-link-not-a-secret")

        let account = SignInModel(prefilledToken: nil, username: "family")
        #expect(account.method == .account)
        #expect(account.username == "family")
        #expect(account.token.isEmpty)
    }

    @Test("A pasted full link signs in with only its token and reaches the archive")
    func signInWithLink() async throws {
        let server = MockServer(handler: FakeArchive.handler(signedIn: "auth-check-token"))
        let store = try await signInStore(server)
        let model = SignInModel(prefilledToken: nil, username: nil)
        model.method = .shareLink
        model.token = "\(server.address.baseURL.absoluteString)/#token=demo-share-link-not-a-secret"

        await model.submit(using: store)

        #expect(model.error == nil)
        guard case let .ready(session) = store.phase else {
            Issue.record("expected .ready, got \(store.phase)")
            return
        }
        #expect(session.stored.role == .token)
        #expect(session.stored.noDownload)
        let post = try #require(server.requests(to: "/auth/token").first)
        let body = try JSONSerialization.jsonObject(with: try #require(post.body)) as? [String: String]
        #expect(body == ["token": "demo-share-link-not-a-secret"])
    }

    @Test("An account sign-in trims the username, sends the password as typed and forgets it afterwards")
    func signInWithAccount() async throws {
        let server = MockServer(handler: FakeArchive.handler())
        let store = try await signInStore(server)
        let model = SignInModel(prefilledToken: nil, username: nil)
        model.username = " admin "
        model.password = " pass word "

        await model.submit(using: store)

        let post = try #require(server.requests(to: "/api/login").first)
        let body = try JSONSerialization.jsonObject(with: try #require(post.body)) as? [String: String]
        #expect(body == ["username": "admin", "password": " pass word "])
        #expect(model.password.isEmpty)
        #expect(store.lastUsername == "admin")
    }

    @Test("Wrong password: the error shows, the screen stays, and the password can be corrected")
    func wrongPassword() async throws {
        let server = MockServer { request in
            request.path == "/api/login"
                ? .json(#"{"detail": "Invalid credentials"}"#, status: 401)
                : .json(#"{"authenticated": false, "auth_required": true}"#)
        }
        let store = try await signInStore(server)
        let model = SignInModel(prefilledToken: nil, username: "admin")
        model.password = "wrong"

        await model.submit(using: store)

        #expect(model.error == .wrongCredentials)
        #expect(model.password == "wrong")
        #expect(model.canSubmit)
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: nil))
    }

    @Test("A 429 turns the button off for the lockout, sends nothing more, then turns it back on")
    func rateLimitLockout() async throws {
        let server = MockServer { request in
            request.path == "/auth/token"
                ? .json(#"{"detail": "Too many login attempts. Try again later."}"#, status: 429)
                : .json(#"{"authenticated": false, "auth_required": true}"#)
        }
        let store = try await signInStore(server)
        let model = SignInModel(prefilledToken: "t", username: nil, lockout: .milliseconds(300))

        await model.submit(using: store)
        #expect(model.error == .api(.rateLimited))
        #expect(model.isLockedOut)
        #expect(!model.canSubmit)

        await model.submit(using: store)
        #expect(server.requests(to: "/auth/token").count == 1)

        for _ in 0..<50 where model.isLockedOut {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!model.isLockedOut)
        #expect(model.canSubmit)
        #expect(server.requests(to: "/auth/token").count == 1, "the lockout ending must not retry")
    }
}
