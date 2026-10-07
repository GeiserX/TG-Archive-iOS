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

    /// The share sheet's header: the file's name beside its thumbnail, or a photo or video symbol until the
    /// thumbnail has loaded. A title-only preview leaves the header's icon blank.
    static func preview(for media: MessageMedia, image: UIImage?) -> SharePreview<Image, Never> {
        let title = DocumentName.display(media.fileName) ?? MediaKindLabel(kind: media.type.rawValue)?.title ?? ""
        if let image { return SharePreview(title, image: Image(uiImage: image)) }
        return SharePreview(title, image: Image(systemName: media.type == .photo ? "photo" : "video"))
    }

    fileprivate func download() async throws -> SentTransferredFile {
        let url = try await loader.file(ref: target.ref, key: target.media.key, fileName: target.media.fileName)
        return SentTransferredFile(url)
    }

    /// A concrete type first, so share targets see an image or a movie (Save Image and Save Video rely on the
    /// `NSPhotoLibraryAddUsageDescription` string in the Info.plist); plain data last, so any file can still go to
    /// Files.
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
