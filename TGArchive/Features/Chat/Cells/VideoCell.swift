import SwiftUI

/// A video or a GIF: the thumbnail when the server made one (it needs ffmpeg), else a dark tile, with a play
/// glyph and the duration. Tapping opens it.
struct VideoCell: View {
    let message: Message
    let media: MessageMedia
    let context: ThreadContext
    @State private var viewing: MediaTarget?
    @Environment(\.displayScale) private var displayScale

    private var isAnimation: Bool { media.type == .animation }

    var body: some View {
        if let reason = MediaUnavailable.reason(for: media, noDownload: context.noDownload) {
            MediaPlaceholder(reason)
                .frame(width: MediaFrame.width)
        } else {
            Button {
                viewing = MediaTarget(ref: context.ref, messageID: message.id, media: media)
            } label: {
                Color.clear
                    .aspectRatio(MediaFrame.aspectRatio(media, fallback: 16.0 / 9.0), contentMode: .fit)
                    .frame(width: MediaFrame.width)
                    .overlay {
                        RemoteImage(endpoint: .thumbnail(size: .large, ref: context.ref, key: media.key),
                                    maxPixelSize: Int((MediaFrame.width * displayScale).rounded(.up))) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { _ in
                            Rectangle().fill(Color(white: 0.15))
                        }
                    }
                    .overlay {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.45))
                            .accessibilityHidden(true)
                    }
                    .overlay(alignment: .bottomLeading) {
                        badge
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .mediaViewer($viewing, canShare: !context.noDownload)
        }
    }

    @ViewBuilder
    private var badge: some View {
        let text = isAnimation ? String(localized: "preview.kind.animation") : MediaFrame.duration(media.duration)
        if let text {
            Text(verbatim: text)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(6)
        }
    }

    private var accessibilityText: Text {
        let kind = Text(LocalizedStringKey(isAnimation ? "preview.kind.animation" : "preview.kind.video"))
        guard !isAnimation, let duration = MediaFrame.duration(media.duration) else { return kind }
        return Text("\(kind), \(duration)")
    }
}
