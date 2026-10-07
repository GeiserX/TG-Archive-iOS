import SwiftUI

/// Placeholder root screen. The onboarding stage replaces it with the connect, sign-in and tab flow.
struct RootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "archivebox")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("app.name")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("root.title")
            Text("app.placeholder")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    RootView()
}
