import SwiftUI

/// A sticker. A static WebP draws as an image at 160 pt, or the tile saying why it is not fetched; an animated
/// `.tgs` or `.webm`, which v1 does not play, shows its emoji at 64 pt, or a sticker glyph when it has none.
struct StickerCell: View {
    let content: StickerContent
    let context: ThreadContext
    @Environment(\.displayScale) private var displayScale

    private let side: CGFloat = 160

    var body: some View {
        Group {
            if content.isStatic, let reason = MediaUnavailable.reason(for: content.media,
                                                                      noDownload: context.noDownload) {
                MediaPlaceholder(reason, height: 96)
                    .frame(width: side)
            } else if content.isStatic {
                RemoteImage(endpoint: .media(ref: context.ref, key: content.media.key),
                            maxPixelSize: Int((side * displayScale).rounded(.up))) { image in
                    image.resizable().scaledToFit()
                } placeholder: { failure in
                    if failure == nil {
                        ProgressView()
                    } else {
                        fallback
                    }
                }
                .frame(width: side, height: side)
            } else {
                fallback
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [String(localized: "preview.kind.sticker"), content.emoji]
            .compactMap(\.self).joined(separator: " ")))
    }

    @ViewBuilder
    private var fallback: some View {
        if let emoji = content.emoji {
            Text(verbatim: emoji)
                .font(.system(size: 64))
        } else {
            Image(systemName: "face.smiling")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(width: 96, height: 96)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
