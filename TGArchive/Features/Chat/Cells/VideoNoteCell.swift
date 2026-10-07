import SwiftUI

/// A round video message: a circle with the thumbnail when there is one, a play glyph and the duration, and
/// its transcript under it when the archive has one. Tapping opens it.
struct VideoNoteCell: View {
    let message: Message
    let media: MessageMedia
    let context: ThreadContext
    @State private var viewing: MediaTarget?
    @Environment(\.displayScale) private var displayScale

    private let diameter: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reason = MediaUnavailable.reason(for: media, noDownload: context.noDownload) {
                MediaPlaceholder(reason, height: 80)
                    .frame(width: diameter)
            } else {
                Button {
                    viewing = MediaTarget(ref: context.ref, messageID: message.id, media: media)
                } label: {
                    circle
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("preview.kind.videoNote"))
                .mediaViewer($viewing, canShare: !context.noDownload)
            }
            TranscriptView(media: media)
                .frame(maxWidth: MediaFrame.width, alignment: .leading)
        }
    }

    private var circle: some View {
        RemoteImage(endpoint: .thumbnail(size: .large, ref: context.ref, key: media.key),
                    maxPixelSize: Int((diameter * displayScale).rounded(.up))) { image in
            image.resizable().scaledToFill()
        } placeholder: { _ in
            Rectangle().fill(Color(white: 0.15))
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay {
            Image(systemName: "play.fill")
                .font(.title)
                .foregroundStyle(.white)
                .shadow(radius: 2)
        }
        .overlay(alignment: .bottom) {
            if let duration = MediaFrame.duration(media.duration) {
                Text(verbatim: duration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(.bottom, 12)
            }
        }
        .contentShape(Circle())
    }
}
