import SwiftUI

/// An image from the archive server, in place of `AsyncImage`, which cannot send the session cookie.
///
/// It loads in `.task(id:)`, so a cell scrolled away cancels its download, and it asks the session's
/// `MediaLoader`, which revalidates with the server on every load. The placeholder gets the failure, nil
/// while loading, so a cell can show the downloads-off or missing tile.
struct RemoteImage<Content: View, Placeholder: View>: View {
    let endpoint: Endpoint
    /// The long side, in pixels, to decode to.
    let maxPixelSize: Int
    private let content: (Image) -> Content
    private let placeholder: (MediaFailure?) -> Placeholder

    @Environment(SessionStore.self) private var store: SessionStore?
    @State private var loaded: (endpoint: Endpoint, image: UIImage)?
    @State private var failure: MediaFailure?

    init(endpoint: Endpoint, maxPixelSize: Int = 1200,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping (MediaFailure?) -> Placeholder) {
        self.endpoint = endpoint
        self.maxPixelSize = maxPixelSize
        self.content = content
        self.placeholder = placeholder
    }

    init(endpoint: Endpoint, maxPixelSize: Int = 1200,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.init(endpoint: endpoint, maxPixelSize: maxPixelSize, content: content) { _ in placeholder() }
    }

    var body: some View {
        Group {
            if let loaded, loaded.endpoint == endpoint {
                content(Image(uiImage: loaded.image))
            } else {
                placeholder(failure)
            }
        }
        .task(id: endpoint) {
            failure = nil
            guard let store, case let .ready(session) = store.phase else { return }
            let loader = MediaLoader.current(for: session, in: store)
            do {
                let image = try await loader.image(for: endpoint, maxPixelSize: maxPixelSize)
                loaded = (endpoint, image)
            } catch {
                let mapped = error as? MediaFailure ?? .failed(APIError.from(transport: error))
                guard !mapped.isCancellation, !Task.isCancelled else { return }
                loaded = nil
                failure = mapped
            }
        }
    }
}

/// The tile for an image that did not load: downloads off for this login, no file, or no connection.
struct MediaStatusTile: View {
    let failure: MediaFailure?

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let failure {
                VStack(spacing: 6) {
                    Image(systemName: symbol(for: failure))
                        .font(.title2)
                        .accessibilityHidden(true)
                    Text(label(for: failure))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .padding(8)
            } else {
                ProgressView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(for failure: MediaFailure) -> String {
        switch failure {
        case .downloadsOff: "arrow.down.circle.dotted"
        case .missing, .undecodable: "photo"
        case .sessionEnded, .failed: "exclamationmark.triangle"
        }
    }

    private func label(for failure: MediaFailure) -> LocalizedStringKey {
        switch failure {
        case .downloadsOff: "media.downloadsOff"
        case .missing, .undecodable: "media.missing"
        case .sessionEnded, .failed: "media.failed"
        }
    }
}
