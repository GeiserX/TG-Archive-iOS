import SwiftUI

/// Where a cell's media lives, and the login's download rule. Cells build every media URL from it.
struct ThreadContext: Equatable, Sendable {
    let ref: String
    /// Downloads are off for this login: no file or thumbnail is ever asked for.
    let noDownload: Bool
}

/// What a tap on a media cell opens: the file of one message in one chat.
struct MediaTarget: Hashable, Sendable {
    let ref: String
    let messageID: Int
    let media: MessageMedia
}

/// The hook a media tap calls. The thread leaves it unset; the media viewer sets it to present itself.
struct OpenMediaAction {
    let handler: @MainActor (MediaTarget) -> Void

    @MainActor
    func callAsFunction(_ target: MediaTarget) { handler(target) }
}

extension EnvironmentValues {
    @Entry var openMedia: OpenMediaAction?
}

/// The tile for media the app does not ask the server for: downloads off, skipped by the archive, not
/// downloaded yet, or a kind this version does not draw.
struct MediaPlaceholder: View {
    let symbol: String
    let title: String
    var height: CGFloat = 120

    init(_ reason: MediaUnavailable, height: CGFloat = 120) {
        symbol = reason.symbol
        title = String(localized: reason.titleKey)
        self.height = height
    }

    init(unsupported kind: MediaType) {
        let label = MediaKindLabel(kind: kind.rawValue)
        symbol = label?.symbol ?? "questionmark.square"
        title = [label?.title, String(localized: "preview.kind.unsupported")].compactMap(\.self)
            .uniqued().joined(separator: " · ")
        height = 72
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.title2)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One line with a glyph for a file that is not fetched, under a voice note or a document.
struct MediaUnavailableLine: View {
    let reason: MediaUnavailable

    var body: some View {
        Label {
            Text(String(localized: reason.titleKey))
        } icon: {
            Image(systemName: reason.symbol)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// A file's frame: its own aspect ratio, kept within sane bounds, so a row does not jump when the image comes.
enum MediaFrame {
    static let width: CGFloat = 240

    static func aspectRatio(_ media: MessageMedia, fallback: CGFloat = 4.0 / 3.0) -> CGFloat {
        guard let width = media.width, let height = media.height, width > 0, height > 0 else { return fallback }
        return min(max(CGFloat(width) / CGFloat(height), 0.5), 2.2)
    }

    /// `m:ss`, or `h:mm:ss` from an hour.
    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return nil }
        let total = Int(seconds.rounded())
        let (hours, minutes, rest) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

extension Sequence where Element: Hashable {
    fileprivate func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
