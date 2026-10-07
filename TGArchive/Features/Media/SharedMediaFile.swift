import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// The original file of a photo or a video, for the share sheet. The file is downloaded only when the user
/// picks where it goes, into the same `tmp/Media` the sign-out wipe deletes.
struct SharedMediaFile: Transferable {
    let target: MediaTarget
    let loader: MediaLoader

    /// The file's type, from its MIME type, else its name, else plain data.
    var contentType: UTType { Self.contentType(of: target.media) }

    static func contentType(of media: MessageMedia) -> UTType {
        if let mime = media.mimeType?.nonBlank, let type = UTType(mimeType: mime) { return type }
        if let name = media.fileName, let dot = name.lastIndex(of: "."),
           let type = UTType(filenameExtension: String(name[name.index(after: dot)...])) {
            return type
        }
        return .data
    }

    /// The file's name as the share sheet's title; the sheet draws the icon for the file's type.
    static func preview(for media: MessageMedia) -> SharePreview<Never, Never> {
        SharePreview(DocumentName.display(media.fileName) ?? MediaKindLabel(kind: media.type.rawValue)?.title ?? "")
    }

    fileprivate func download() async throws -> SentTransferredFile {
        let url = try await loader.file(ref: target.ref, key: target.media.key, fileName: target.media.fileName)
        return SentTransferredFile(url)
    }

    /// A concrete type first, so share targets see an image or a movie (Save Image and Save Video also need a
    /// photo-library usage string in the Info.plist); plain data last, so any file can still go to Files.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg) { try await $0.download() }
            .exportingCondition { $0.contentType.conforms(to: .jpeg) }
        FileRepresentation(exportedContentType: .png) { try await $0.download() }
            .exportingCondition { $0.contentType.conforms(to: .png) }
        FileRepresentation(exportedContentType: .mpeg4Movie) { try await $0.download() }
            .exportingCondition { $0.contentType.conforms(to: .mpeg4Movie) }
        FileRepresentation(exportedContentType: .quickTimeMovie) { try await $0.download() }
            .exportingCondition { $0.contentType.conforms(to: .quickTimeMovie) }
        FileRepresentation(exportedContentType: .data) { try await $0.download() }
    }
}
