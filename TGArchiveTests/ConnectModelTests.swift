import Foundation
import Testing
@testable import TGArchive

@MainActor
@Suite("Connect screen")
struct ConnectModelTests {
    private let vault = MemoryVault()

    @Test("Pasting a share link probes its server and opens sign-in with the token, even when it is not hex")
    func pasteShareLink() async throws {
        let server = MockServer(prefix: FakeArchive.prefix, handler: FakeArchive.handler())
        let store = FakeArchive.store(vault: vault)
        let model = ConnectModel()
        let link = "\(server.address.baseURL.absoluteString)/#token=demo-share-link-not-a-secret"

        let moved = await model.paste(["", "  \(link)\n"], using: store)

        #expect(moved)
        #expect(model.address == link)
        #expect(model.error == nil)
        #expect(!model.isConnecting)
        #expect(store.phase == .signIn(server.address, prefilledToken: "demo-share-link-not-a-secret", reason: nil))
        #expect(server.requests.map(\.path) == ["/archive/api/auth/check"])
    }

    @Test("A typed address goes to sign-in with nothing prefilled")
    func typedAddress() async throws {
        let server = MockServer(handler: FakeArchive.handler())
        let store = FakeArchive.store(vault: vault)
        let model = ConnectModel(address: server.address.baseURL.absoluteString)

        #expect(await model.connect(using: store))
        #expect(store.phase == .signIn(server.address, prefilledToken: nil, reason: nil))
    }

    @Test("Nothing to connect to sends nothing")
    func emptyInput() async {
        let store = FakeArchive.store(vault: vault)
        let model = ConnectModel(address: "   ")
        #expect(!model.canConnect)
        #expect(!(await model.connect(using: store)))
        #expect(!(await model.paste(["", " \n"], using: store)))
        #expect(model.error == nil)
        #expect(store.phase == .restoring)
    }

    @Test("A failed probe keeps the address, shows why, and offers the setup docs only for a server with no login mode",
          arguments: [
              (MockServer.Response.json("<!doctype html><html></html>"), SessionError.api(.notAnArchiveServer), false),
              (.json(#"{"authenticated": false, "auth_required": true, "setup_required": true}"#), .setupRequired, true),
              (.json(#"{"authenticated": true, "auth_required": true, "proxy_auth": true}"#), .proxyAuthUnsupported, false),
              (.transportFailure(.appTransportSecurityRequiresSecureConnection),
               .api(.transport(.appTransportSecurityRequiresSecureConnection)), false),
          ])
    func probeFailures(_ response: MockServer.Response, _ expected: SessionError, _ needsSetup: Bool) async {
        let server = MockServer { _ in response }
        let store = FakeArchive.store(vault: vault)
        let typed = server.address.baseURL.absoluteString
        let model = ConnectModel(address: typed)

        #expect(!(await model.connect(using: store)))
        #expect(model.error == expected)
        #expect(model.needsServerSetup == needsSetup)
        #expect(model.address == typed)
        #expect(model.canConnect)
        #expect(store.phase == .restoring)
    }

    @Test("Plain http to a remote server is explained as needing https")
    func httpsSentence() {
        let message = SessionError.api(.transport(.appTransportSecurityRequiresSecureConnection)).message
        #expect(message == String(localized: "api.error.httpsRequired"))
        #expect(message != String(localized: "api.error.offline"))
    }

    @Test("An open server goes straight to the archive")
    func anonymousServer() async throws {
        let server = MockServer { _ in .json(#"{"authenticated": false, "auth_required": false}"#) }
        let store = FakeArchive.store(vault: vault)
        let model = ConnectModel(address: server.address.baseURL.absoluteString)

        #expect(await model.connect(using: store))
        guard case let .ready(session) = store.phase else {
            Issue.record("expected .ready, got \(store.phase)")
            return
        }
        #expect(session.stored.role == .anonymous)
    }
}
