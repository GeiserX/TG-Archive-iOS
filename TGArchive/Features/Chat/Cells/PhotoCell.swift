import SwiftUI

/// A photo: the 400 px thumbnail at the photo's own aspect ratio. Tapping opens it.
struct PhotoCell: View {
    let message: Message
    let media: MessageMedia
    let context: ThreadContext
    @Environment(\.openMedia) private var openMedia
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let reason = MediaUnavailable.reason(for: media, noDownload: context.noDownload) {
            MediaPlaceholder(reason)
                .frame(width: MediaFrame.width)
        } else {
            Button {
                openMedia?(MediaTarget(ref: context.ref, messageID: message.id, media: media))
            } label: {
                Color.clear
                    .aspectRatio(MediaFrame.aspectRatio(media), contentMode: .fit)
                    .frame(width: MediaFrame.width)
                    .overlay {
                        RemoteImage(endpoint: .thumbnail(size: .large, ref: context.ref, key: media.key),
                                    maxPixelSize: Int((MediaFrame.width * displayScale).rounded(.up))) { image in
                            image.resizable().scaledToFill()
                        } placeholder: { failure in
                            MediaStatusTile(failure: failure)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("preview.kind.photo"))
            .accessibilityAddTraits(.isImage)
        }
    }
}
