import SwiftUI

/// A round avatar: the chat's photo from the server, or its initials on a colour picked from the ref.
struct AvatarView: View {
    /// The avatar route, or nil when the chat has no photo (no request is sent).
    let endpoint: Endpoint?
    let title: String
    /// Picks the initials' colour, stable across launches.
    let seed: String
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 52
    /// Grows with Dynamic Type, but stops before it crowds the text at the accessibility sizes.
    private var size: CGFloat { min(scaledSize, 80) }
    @Environment(\.displayScale) private var displayScale

    init(endpoint: Endpoint?, title: String, seed: String) {
        self.endpoint = endpoint
        self.title = title
        self.seed = seed
    }

    /// A chat list row's avatar.
    init(chat: Chat) {
        self.init(endpoint: chat.avatarURL == nil ? nil : .avatar(ref: chat.ref), title: chat.displayTitle,
                  seed: chat.ref)
    }

    var body: some View {
        Group {
            if let endpoint {
                RemoteImage(endpoint: endpoint, maxPixelSize: Int((size * displayScale).rounded(.up))) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Circle()
            .fill(Self.color(for: seed).gradient)
            .overlay {
                Text(Self.initials(of: title))
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
    }

    /// Up to two letters: the first of the first two words.
    nonisolated static func initials(of title: String) -> String {
        let words = title.split(whereSeparator: { $0.isWhitespace || $0 == "@" })
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }

    /// Our own palette, never the messenger's blue; all of it keeps white initials readable in both modes.
    private nonisolated static let palette: [Color] = [.red, .orange, .green, .teal, .indigo, .purple, .pink, .brown]

    /// FNV-1a over the bytes, so the colour does not change between launches as `hashValue` would.
    nonisolated static func paletteIndex(for seed: String) -> Int {
        var hash: UInt32 = 2_166_136_261
        for byte in seed.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Int(hash % UInt32(palette.count))
    }

    static func color(for seed: String) -> Color { palette[paletteIndex(for: seed)] }
}
