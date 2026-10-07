import Foundation
import Security

/// Where the session is kept. The Keychain in the app; an in-memory stand-in in tests.
protocol SessionVault: Sendable {
    func load() throws -> StoredSession?
    func save(_ session: StoredSession) throws
    func delete() throws
}

/// One generic-password item holding the JSON of the `StoredSession`: this device only, after first unlock,
/// never synchronized. It survives deleting the app, which the reinstall cleanup in `SessionStore` handles.
struct KeychainStore: SessionVault {
    struct Failure: Error, Equatable {
        let status: OSStatus
    }

    let service: String
    let account: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "io.github.geiserx.tgarchive") + ".session",
         account: String = "current") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    /// The stored session, or nil. An item that no longer decodes is deleted and reads as nil.
    func load() throws -> StoredSession? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw Failure(status: status) }
        guard let session = try? JSONDecoder().decode(StoredSession.self, from: data) else {
            try delete()
            return nil
        }
        return session
    }

    func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        } else if status != errSecSuccess {
            throw Failure(status: status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
