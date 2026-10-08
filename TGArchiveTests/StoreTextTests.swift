import Foundation
import ImageIO
import Testing

/// The checkout this test file was compiled from. The tests run in a simulator on the Mac that built them,
/// so the repository's docs and workflows are readable from here.
private let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private func repositoryFile(_ path: String) throws -> String {
    try String(contentsOf: repositoryRoot.appending(path: path), encoding: .utf8)
}

/// The `## Field` sections of a store text file, each trimmed.
private func storeFields(_ language: String) throws -> [String: String] {
    let text = try repositoryFile("docs/app-store/description.\(language).md")
    var fields: [String: String] = [:]
    var current: String?
    var lines: [Substring] = []
    func flush() {
        if let current { fields[current] = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.hasPrefix("## ") {
            flush()
            current = String(line.dropFirst(3))
            lines = []
        } else {
            lines.append(line)
        }
    }
    flush()
    return fields
}

private func field(_ fields: [String: String], _ name: String) throws -> String {
    let value = try #require(fields[name], "no \(name) field")
    try #require(!value.isEmpty, "\(name) is empty")
    return value
}

/// "Telegram" as a word of its own, not as part of the project name "Telegram-Archive".
private var bareTelegram: Regex<Substring> { /(?i)telegram(?!-archive)/ }

private let repositoryURL = "https://github.com/GeiserX/TG-Archive-iOS"

/// The App Store texts in `docs/app-store/` fit App Store Connect's limits and keep the naming rules.
@Suite("Store text")
struct StoreTextTests {
    static let opening = [
        "en": "TG Archive is the iOS client for the open-source Telegram-Archive server you run yourself.",
        "es": "TG Archive es el cliente de iOS para el servidor de código abierto Telegram-Archive que ejecutas tú mismo.",
    ]
    static let disclosure = [
        "en": "TG Archive is part of the open-source Telegram-Archive project and is independent of Telegram; "
            + "the server you run uses the Telegram API.",
        "es": "TG Archive forma parte del proyecto de código abierto Telegram-Archive y es independiente de Telegram; "
            + "el servidor que ejecutas usa la API de Telegram.",
    ]

    @Test("Every field fits App Store Connect's limits", arguments: ["en", "es"])
    func limits(_ language: String) throws {
        let fields = try storeFields(language)
        #expect(try field(fields, "Name") == "TG Archive")
        #expect(try field(fields, "Subtitle").count <= 30)
        #expect(try field(fields, "Promotional text").count <= 170)
        #expect(try field(fields, "Keywords").utf8.count <= 100)
        #expect(try field(fields, "Description").count <= 4000)
    }

    @Test("The description opens with the client line and ends with the disclosure", arguments: ["en", "es"])
    func description(_ language: String) throws {
        let description = try field(try storeFields(language), "Description")
        #expect(description.hasPrefix(try #require(Self.opening[language])))
        #expect(description.hasSuffix(try #require(Self.disclosure[language])))
        #expect(description.contains(repositoryURL), "the GPL needs the source link")
        // "Telegram" on its own appears only in the closing disclosure paragraph.
        let paragraphs = description.components(separatedBy: "\n\n")
        #expect(paragraphs.dropLast().filter { $0.contains(bareTelegram) } == [])
    }

    @Test("No text calls the app unofficial, and Telegram stays out of the name, subtitle and keywords",
          arguments: ["en", "es"])
    func wording(_ language: String) throws {
        let text = try repositoryFile("docs/app-store/description.\(language).md").lowercased()
        #expect(!text.contains("unofficial"))
        #expect(!text.contains("no oficial"))
        let fields = try storeFields(language)
        for name in ["Name", "Subtitle", "Keywords"] {
            #expect(!(try field(fields, name)).contains(bareTelegram), "\(name) names Telegram")
        }
    }

    @Test("Keywords are comma-separated without spaces, unique, and repeat no word of the name or subtitle",
          arguments: ["en", "es"])
    func keywords(_ language: String) throws {
        let fields = try storeFields(language)
        let keywords = try field(fields, "Keywords").lowercased()
        #expect(!keywords.contains(", ") && !keywords.hasSuffix(","))
        let terms = keywords.split(separator: ",").map(String.init)
        #expect(Set(terms).count == terms.count, "a keyword repeats")
        let titleWords = Set((try field(fields, "Name") + " " + field(fields, "Subtitle")).lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init))
        let keywordWords = Set(terms.flatMap { $0.split(separator: " ").map(String.init) })
        #expect(keywordWords.intersection(titleWords).sorted() == [])
    }

    @Test("The support and privacy URLs point at this repository, and the privacy policy exists",
          arguments: ["en", "es"])
    func urls(_ language: String) throws {
        let fields = try storeFields(language)
        #expect(try field(fields, "Support URL") == repositoryURL + "/issues")
        #expect(try field(fields, "Privacy policy URL") == repositoryURL + "/blob/main/PRIVACY.md")
        #expect(FileManager.default.fileExists(atPath: repositoryRoot.appending(path: "PRIVACY.md").path))
    }

    @Test("The review notes template keeps placeholders, fits the Notes field, and names no host")
    func reviewNotes() throws {
        let template = try repositoryFile("docs/app-store/review-notes-template.md")
        for placeholder in ["<DEMO_URL>", "<VIEWER_USERNAME>", "<VIEWER_PASSWORD>", "<SHARE_LINK>"] {
            #expect(template.contains(placeholder), "missing \(placeholder)")
        }
        let notes = try #require(template.components(separatedBy: "\n## Notes\n").last)
        #expect(notes.trimmingCharacters(in: .whitespacesAndNewlines).count <= 4000)
        #expect(notes.contains(try #require(Self.disclosure["en"])))
        #expect(!template.lowercased().contains("unofficial"))
        // Where the recording was made is never stated to App Review.
        #expect(!template.lowercased().contains("simulator"))
        // The only addresses written down are the public project repositories.
        let urls = template.matches(of: /https?:\/\/[^\s)`>]+/).map { String($0.output) }
        #expect(urls.filter { !$0.hasPrefix("https://github.com/GeiserX/") } == [])
    }
}

/// The release path: the icon the archive ships and the values `release.yml` repeats from `project.yml`.
@Suite("Release path")
struct ReleasePathTests {
    /// The first value of `key:` in a YAML file, as `release.yml`'s own awk check reads it.
    private func yamlValue(_ key: String, in text: String) throws -> String {
        let line = try #require(text.split(separator: "\n").first {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + ":")
        }, "no \(key) line")
        return line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
    }

    @Test("The app ships the AppIcon set as its primary icon")
    func appIconInBundle() throws {
        let info = try #require(Bundle.main.infoDictionary)
        try #require(Bundle.main.bundleIdentifier == "io.github.geiserx.tgarchive", "tests are not hosted in the app")
        let icons = try #require(info["CFBundleIcons"] as? [String: Any], "no CFBundleIcons: the icon did not compile")
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
    }

    @Test("The icon set holds one 1024 px universal iOS icon without alpha")
    func appIconFile() throws {
        let set = repositoryRoot.appending(path: "TGArchive/Resources/Assets.xcassets/AppIcon.appiconset")
        let contents = try JSONSerialization.jsonObject(with: Data(contentsOf: set.appending(path: "Contents.json")))
        let images = try #require((contents as? [String: Any])?["images"] as? [[String: Any]])
        #expect(images.count == 1)
        let image = try #require(images.first)
        #expect(image["idiom"] as? String == "universal")
        #expect(image["platform"] as? String == "ios")
        #expect(image["size"] as? String == "1024x1024")
        let file = try #require(image["filename"] as? String)
        let source = try #require(CGImageSourceCreateWithURL(set.appending(path: file) as CFURL, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 1024)
        #expect(properties[kCGImagePropertyPixelHeight] as? Int == 1024)
        #expect(properties[kCGImagePropertyHasAlpha] as? Bool != true, "App Store icons must be opaque")
    }

    @Test("release.yml signs with the team, bundle id and profile that project.yml declares")
    func releaseMirrorsProject() throws {
        let project = try repositoryFile("project.yml")
        let release = try repositoryFile(".github/workflows/release.yml")
        #expect(try yamlValue("TEAM_ID", in: release) == yamlValue("DEVELOPMENT_TEAM", in: project))
        #expect(try yamlValue("BUNDLE_ID", in: release) == yamlValue("PRODUCT_BUNDLE_IDENTIFIER", in: project))
        #expect(try yamlValue("APP_PROFILE_NAME", in: release)
            == yamlValue("PROVISIONING_PROFILE_SPECIFIER", in: project))
        #expect(try yamlValue("BUNDLE_ID", in: release) == Bundle.main.bundleIdentifier)
    }

    @Test("The version a release tag must match is the one the app reports")
    func marketingVersion() throws {
        let version = try yamlValue("MARKETING_VERSION", in: try repositoryFile("project.yml"))
        #expect(version.wholeMatch(of: /\d+\.\d+\.\d+/) != nil)
        #expect(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String == version)
    }
}
