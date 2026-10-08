import SwiftUI

/// The app's name and version, the disclosure, and the links the GPL and App Review need.
struct AboutView: View {
    static let privacyPolicy = URL(string: "https://github.com/GeiserX/TG-Archive-iOS/blob/main/PRIVACY.md")!
    static let sourceCode = URL(string: "https://github.com/GeiserX/TG-Archive-iOS")!
    static let license = URL(string: "https://github.com/GeiserX/TG-Archive-iOS/blob/main/LICENSE")!

    /// "0.1.0 (1)", from the bundle.
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("app.name")
                        .font(.title2.bold())
                    Text("about.version \(Self.version)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("about.version")
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section {
                Text("about.disclaimer")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("about.disclaimer")
            }

            Section {
                Link(destination: Self.privacyPolicy) { Text("about.privacy") }
                Link(destination: Self.sourceCode) { Text("about.source") }
                Link(destination: Self.license) { Text("about.license") }
            } footer: {
                Text("about.license.footer")
            }
        }
        .navigationTitle(Text("about.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AboutView() }
}
