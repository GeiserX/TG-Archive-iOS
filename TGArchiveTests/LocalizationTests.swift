import Foundation
import Testing

/// Every string the app shows exists in English and in Spanish.
@Suite("Localization")
struct LocalizationTests {
    private func table(_ language: String, _ name: String) throws -> [String: String] {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "strings", subdirectory: nil,
                                                localization: language), "no \(language) \(name).strings")
        return try #require(NSDictionary(contentsOf: url) as? [String: String])
    }

    @Test("English and Spanish have the same keys, none empty", arguments: ["Localizable", "InfoPlist"])
    func sameKeys(_ name: String) throws {
        let en = try table("en", name)
        let es = try table("es", name)
        #expect(!en.isEmpty)
        #expect(Set(en.keys).subtracting(es.keys).sorted() == [], "missing in Spanish")
        #expect(Set(es.keys).subtracting(en.keys).sorted() == [], "missing in English")
        #expect(en.filter { $0.value.isEmpty }.keys.sorted() == [])
        #expect(es.filter { $0.value.isEmpty }.keys.sorted() == [])
    }

    @Test("The About screen carries the disclosure word for word and never calls the app unofficial")
    func disclosure() throws {
        let en = try table("en", "Localizable")
        let es = try table("es", "Localizable")
        #expect(en["about.disclaimer"] == "TG Archive is part of the open-source Telegram-Archive project and is independent "
            + "of Telegram. It reads backups made by Telegram-Archive, a server you run yourself, which uses the Telegram API.")
        #expect(en["about.disclaimer"]?.lowercased().contains("unofficial") == false)
        #expect(es["about.disclaimer"]?.lowercased().contains("no es oficial") == false)
    }
}
