import SwiftUI

/// A voice note or an audio file: a play button, the duration over a progress bar, and the newest finished
/// transcript under it as text that folds open. Playback comes with the media viewer; the button calls its
/// hook.
struct VoiceCell: View {
    let message: Message
    let media: MessageMedia
    let context: ThreadContext
    @Environment(\.openMedia) private var openMedia
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 40

    private var reason: MediaUnavailable? {
        MediaUnavailable.reason(for: media, noDownload: context.noDownload)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    openMedia?(MediaTarget(ref: context.ref, messageID: message.id, media: media))
                } label: {
                    Image(systemName: "play.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: buttonSize, height: buttonSize)
                        .background(reason == nil ? Color.accentColor : Color.secondary, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(reason != nil)
                .accessibilityLabel(Text("chat.play"))
                VStack(alignment: .leading, spacing: 4) {
                    if media.type == .audio {
                        Text(verbatim: AudioTitle.make(media))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    ProgressView(value: 0)
                        .tint(.accentColor)
                        .accessibilityHidden(true)
                    HStack(spacing: 6) {
                        Image(systemName: media.type == .voice ? "mic.fill" : "music.note")
                            .accessibilityHidden(true)
                        if let duration = MediaFrame.duration(media.duration) {
                            Text(verbatim: duration).monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
            if let reason {
                MediaUnavailableLine(reason: reason)
            }
            TranscriptView(media: media)
        }
        .frame(width: MediaFrame.width, alignment: .leading)
    }

    private var accessibilityText: Text {
        let kind = Text(LocalizedStringKey(media.type == .voice ? "preview.kind.voice" : "preview.kind.audio"))
        guard let duration = MediaFrame.duration(media.duration) else { return kind }
        return Text("\(kind), \(duration)")
    }
}

/// An audio file's name without the archive's numeric prefix.
enum AudioTitle {
    static func make(_ media: MessageMedia) -> String {
        DocumentName.display(media.fileName) ?? String(localized: "preview.kind.audio")
    }
}

/// The newest finished transcript of a voice note or a round video, three lines folded, the rest on a tap.
struct TranscriptView: View {
    let media: MessageMedia
    @State private var expanded = false

    /// About three lines in a cell; a shorter transcript shows whole, without the toggle.
    static let foldedLength = 120

    /// The newest `done` transcript with text; the server lists them newest first.
    static func text(of media: MessageMedia) -> String? {
        media.transcripts?.first { $0.status == "done" && $0.text?.nonBlank != nil }?.text?.nonBlank
    }

    var body: some View {
        if let text = Self.text(of: media) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: text)
                    .font(.callout)
                    .lineLimit(expanded ? nil : 3)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if text.count > Self.foldedLength {
                    Button(LocalizedStringKey(expanded ? "chat.transcript.less" : "chat.transcript.more")) {
                        withAnimation { expanded.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("chat.transcript"))
        }
    }
}
