import Foundation
import Testing
@testable import TGArchive

@Suite("Server addresses and share links")
struct ServerAddressTests {
    @Test("Accepted forms and the base URL each gives",
          arguments: [
              ("archive.example.com", "https://archive.example.com"),
              ("  archive.example.com/  \n", "https://archive.example.com"),
              ("archive.example.com:8000", "https://archive.example.com:8000"),
              ("http://192.168.1.20:8000", "http://192.168.1.20:8000"),
              ("HTTP://Archive.Example.com", "http://Archive.Example.com"),
              ("https://example.com/archive/", "https://example.com/archive"),
              ("https://example.com/tg/archive?x=1", "https://example.com/tg/archive"),
              ("http://127.0.0.1:8000", "http://127.0.0.1:8000"),
              ("localhost:8000", "https://localhost:8000"),
              ("http://[::1]:8000", "http://[::1]:8000"),
              ("https://user:pass@example.com", "https://example.com"),
          ])
    func accepted(_ text: String, _ base: String) throws {
        let parsed = try #require(ServerAddress.parse(text))
        #expect(parsed.address.baseURL.absoluteString == base)
        #expect(parsed.token == nil)
    }

    @Test("Rejected input", arguments: ["", "   ", "ftp://example.com", "https://", "http:///path", "two words.com",
                                        "mailto:someone@example.com://x"])
    func rejected(_ text: String) {
        #expect(ServerAddress.parse(text) == nil)
    }

    @Test("A share link splits into the address and the token")
    func shareLink() throws {
        let hex = String(repeating: "ab12", count: 16)
        let parsed = try #require(ServerAddress.parse("https://example.com/archive/#token=\(hex)"))
        #expect(parsed.address.baseURL.absoluteString == "https://example.com/archive")
        #expect(parsed.token == hex)
    }

    @Test("A token that is not 64 hex characters passes through untouched")
    func nonHexToken() throws {
        let parsed = try #require(ServerAddress.parse("http://127.0.0.1:8000/#token=demo-share-link-not-a-secret"))
        #expect(parsed.address.baseURL.absoluteString == "http://127.0.0.1:8000")
        #expect(parsed.token == "demo-share-link-not-a-secret")

        let odd = try #require(ServerAddress.parse("example.com#token=Ab%2F_x&lang=en"))
        #expect(odd.token == "Ab%2F_x")
        #expect(ServerAddress.parse("example.com/#token=")?.token == nil)
        #expect(ServerAddress.parse("example.com/#other=1")?.token == nil)
    }

    @Test("Every request is built under the path prefix, never at the root")
    func prefixKept() throws {
        let address = try #require(ServerAddress.parse("https://example.com/tg")).address
        #expect(Endpoint.authCheck.url(base: address.baseURL).absoluteString == "https://example.com/tg/api/auth/check")
        #expect(Endpoint.tokenLogin.url(base: address.baseURL).absoluteString == "https://example.com/tg/auth/token")
        #expect(Endpoint.thumbnail(size: .large, ref: "Ab_c-1", key: "12_photo").url(base: address.baseURL)
            .absoluteString == "https://example.com/tg/media/thumb/400/Ab_c-1/12_photo")
    }

    @Test("The address survives the Keychain round trip, and the host is shown plainly")
    func codable() throws {
        let address = try #require(ServerAddress.parse("http://archive.local:8000/x")).address
        let decoded = try JSONDecoder().decode(ServerAddress.self, from: JSONEncoder().encode(address))
        #expect(decoded == address)
        #expect(address.host == "archive.local")
        #expect(!address.isHTTPS)
        #expect(try #require(ServerAddress.parse("example.com")).address.isHTTPS)
    }
}
