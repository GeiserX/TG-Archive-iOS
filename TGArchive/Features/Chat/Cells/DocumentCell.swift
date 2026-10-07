import QuickLook
import SwiftUI

/// A file: an icon, its name and its size. Tapping downloads it into `tmp/Media` and opens it in Quick Look,
/// which also shares it.
struct DocumentCell: View {
    let message: Message
    let media: MessageMedia
    let context: ThreadContext
    @Environment(SessionStore.self) private var store: SessionStore?
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 44
    @State private var download: Task<Void, Never>?
    @State private var failure: MediaFailure?
    @State private var preview: URL?

    private var reason: MediaUnavailable? {
        MediaUnavailable.reason(for: media, noDownload: context.noDownload)
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Group {
                    if download != nil {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: DocumentName.symbol(for: media))
                    }
                }
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
                    } else if let failure {
                        Label(DocumentCell.failureKey(failure), systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(reason != nil || download != nil)
        .frame(width: MediaFrame.width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .quickLookPreview($preview)
        // The cancelled task clears `download` itself when it ends, so a new download never starts beside it.
        .onDisappear { download?.cancel() }
    }

    /// Downloads the file through the session's loader, which reports a 401 to the session store.
    private func open() {
        guard download == nil, let store, case let .ready(session) = store.phase else { return }
        let loader = MediaLoader.current(for: session, in: store)
        failure = nil
        download = Task {
            do {
                let url = try await loader.file(ref: context.ref, key: media.key, fileName: media.fileName)
                if !Task.isCancelled { preview = url }
            } catch {
                let mapped = error as? MediaFailure ?? .failed(APIError.from(transport: error))
                if !mapped.isCancellation, !Task.isCancelled { failure = mapped }
            }
            download = nil
        }
    }

    static func failureKey(_ failure: MediaFailure) -> LocalizedStringKey {
        switch failure {
        case .downloadsOff: "media.downloadsOff"
        case .missing, .undecodable: "chat.file.missing"
        case .sessionEnded, .failed: "media.failed"
        }
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
