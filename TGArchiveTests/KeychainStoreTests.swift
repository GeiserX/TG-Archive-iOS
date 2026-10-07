import Foundation
import Security
import Testing
@testable import TGArchive

@Suite("Keychain store")
struct KeychainStoreTests {
    /// Each test uses its own service, so the app's real item is never touched.
    private let store = KeychainStore(service: "io.github.geiserx.tgarchive.tests.\(UUID().uuidString)")

    private static let session = StoredSession(
        server: ServerAddress.parse("https://example.com/tg")!.address,
        cookie: "cookie-value",
        cookieExpires: Date(timeIntervalSince1970: 1_800_000_000),
        username: "family",
        role: .viewer,
        noDownload: true
    )

    @Test("Save, load, overwrite and delete one item")
    func roundTrip() throws {
        defer { try? store.delete() }
        #expect(try store.load() == nil)
        try store.save(Self.session)
        #expect(try store.load() == Self.session)

        let other = StoredSession(server: Self.session.server, cookie: nil, cookieExpires: nil, username: nil,
                                  role: .anonymous, noDownload: false)
        try store.save(other)
        #expect(try store.load() == other)

        try store.delete()
        #expect(try store.load() == nil)
        try store.delete()
    }

    @Test("The item stays on this device, readable after first unlock, never synchronized")
    func attributes() throws {
        defer { try? store.delete() }
        try store.save(Self.session)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: "current",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let attributes = try #require(result as? [String: Any])
        #expect(attributes[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect((attributes[kSecAttrSynchronizable as String] as? Bool ?? false) == false)
    }

    @Test("An item that no longer decodes reads as nil and is removed")
    func corruptItem() throws {
        defer { try? store.delete() }
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
            kSecAttrAccount as String: "current",
            kSecValueData as String: Data("not json".utf8),
        ]
        #expect(SecItemAdd(add as CFDictionary, nil) == errSecSuccess)
        #expect(try store.load() == nil)
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: store.service,
        ]
        #expect(SecItemCopyMatching(probe as CFDictionary, nil) == errSecItemNotFound)
    }
}
