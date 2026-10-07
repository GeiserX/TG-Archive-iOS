import SwiftUI

/// A file: an icon, its name and its size. Tapping opens it in Quick Look, through the media viewer's hook.
struct DocumentCell: View {
    let message: Message
    let media: MessageMedia
    let context: ThreadContext
    @Environment(\.openMedia) private var openMedia
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44

    private var reason: MediaUnavailable? {
        MediaUnavailable.reason(for: media, noDownload: context.noDownload)
    }

    var body: some View {
        Button {
            openMedia?(MediaTarget(ref: context.ref, messageID: message.id, media: media))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: DocumentName.symbol(for: media))
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: iconSize, height: iconSize)
                    .background(reason == nil ? Color.accentColor : Color.secondary,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: DocumentName.display(media.fileName) ?? String(localized: "preview.kind.document"))
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                    if let size = media.fileSize, size > 0 {
                        Text(Int64(size), format: .byteCount(style: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let reason {
                        MediaUnavailableLine(reason: reason)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reason != nil)
        .frame(width: MediaFrame.width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// How a file's name reads in a cell.
enum DocumentName {
    /// The name without the numeric prefix the archive adds to keep names unique (`1543569123_plan.png`).
    static func display(_ fileName: String?) -> String? {
        guard let name = fileName?.nonBlank else { return nil }
        if let underscore = name.firstIndex(of: "_"), underscore > name.startIndex,
           name[..<underscore].allSatisfy(\.isNumber), name.index(after: underscore) < name.endIndex {
            return String(name[name.index(after: underscore)...])
        }
        return name
    }

    static func symbol(for media: MessageMedia) -> String {
        let mime = media.mimeType?.lowercased() ?? ""
        if mime.hasPrefix("image/") { return "photo" }
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime == "application/pdf" { return "doc.richtext" }
        if mime.contains("zip") || mime.contains("compressed") { return "doc.zipper" }
        return "doc.fill"
    }
}
