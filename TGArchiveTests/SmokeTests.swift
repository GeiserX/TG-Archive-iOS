import Foundation
import Testing

/// The unit tests run hosted in the app, so `Bundle.main` is TGArchive.app. Each test first checks that,
/// so a test bundle that loses its host fails here instead of reading the wrong Info.plist.
@Suite("Smoke")
struct SmokeTests {
    private static let appBundleID = "io.github.geiserx.tgarchive"

    private var appBundle: Bundle {
        get throws {
            let bundle = Bundle.main
            try #require(bundle.bundleIdentifier == Self.appBundleID, "tests are not hosted in the app")
            return bundle
        }
    }

    @Test("The display name is TG Archive")
    func displayName() throws {
        let info = try #require(try appBundle.infoDictionary)
        #expect(info["CFBundleDisplayName"] as? String == "TG Archive")
    }

    @Test("The privacy manifest declares no tracking and only the UserDefaults reason CA92.1")
    func privacyManifest() throws {
        let url = try #require(try appBundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        let manifest = try #require(plist as? [String: Any])

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty == true)
        #expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true)

        let accessed = try #require(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        #expect(accessed.count == 1)
        #expect(accessed.first?["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategoryUserDefaults")
        #expect(accessed.first?["NSPrivacyAccessedAPITypeReasons"] as? [String] == ["CA92.1"])
    }
}
