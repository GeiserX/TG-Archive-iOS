import AVKit
import SwiftUI

extension View {
    /// Presents the full-screen media viewer while `target` is set. Sharing is offered only when the login may
    /// download files.
    func mediaViewer(_ target: Binding<MediaTarget?>, canShare: Bool) -> some View {
        fullScreenCover(item: target) { target in
            MediaViewer(target: target, canShare: canShare)
        }
    }
}

/// A photo, a video, a GIF or a round video on a black background: the photo zooms and pans, the videos play
/// in the system player. A Share button hands the original file to the share sheet, downloaded only when the
/// user picks where it goes.
struct MediaViewer: View {
    let target: MediaTarget
    let canShare: Bool

    @Environment(SessionStore.self) private var store: SessionStore?
    @Environment(\.dismiss) private var dismiss

    private var session: Session? {
        guard let store, case let .ready(session) = store.phase else { return nil }
        return session
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let session, let store {
                    content(session: session, store: store)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("media.viewer.done") { dismiss() }
                        .accessibilityIdentifier("media.viewer.done")
                }
                if canShare, let session, let store {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: SharedMediaFile(target: target,
                                                        loader: MediaLoader.current(for: session, in: store)),
                                  preview: SharedMediaFile.preview(for: target.media)) {
                            Label("media.viewer.share", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("media.viewer.share")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black.opacity(0.6), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { AudioPlayback.pauseCurrent() }
    }

    @ViewBuilder
    private func content(session: Session, store: SessionStore) -> some View {
        switch target.media.type {
        case .video, .animation, .videoNote:
            VideoViewer(target: target, client: session.client) { await store.sessionEnded(session.client) }
        default:
            PhotoViewer(target: target, loader: MediaLoader.current(for: session, in: store))
        }
    }
}

/// The original photo, decoded at up to 4096 px, over its thumbnail while it loads.
private struct PhotoViewer: View {
    let target: MediaTarget
    let loader: MediaLoader

    @State private var image: UIImage?
    @State private var failure: MediaFailure?

    var body: some View {
        Group {
            if let image {
                ZoomableImage(image: image, label: String(localized: "preview.kind.photo"))
                    .ignoresSafeArea()
                    .accessibilityIdentifier("media.viewer.photo")
            } else {
                RemoteImage(endpoint: .thumbnail(size: .large, ref: target.ref, key: target.media.key),
                            maxPixelSize: 400) { thumbnail in
                    thumbnail.resizable().scaledToFit()
                } placeholder: {
                    Color.clear
                }
                .overlay {
                    if let failure {
                        MediaStatusTile(failure: failure)
                            .frame(maxWidth: 260, maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        ProgressView().tint(.white)
                    }
                }
            }
        }
        .task(id: target) {
            do {
                image = try await loader.image(for: .media(ref: target.ref, key: target.media.key), maxPixelSize: 4096)
            } catch {
                let mapped = error as? MediaFailure ?? .failed(APIError.from(transport: error))
                guard !mapped.isCancellation, !Task.isCancelled else { return }
                failure = mapped
            }
        }
    }
}

/// The system video player. A GIF loops without sound, as in a chat; a video and a round video play once. A
/// 401 for the file ends the session like any other media route.
private struct VideoViewer: View {
    let target: MediaTarget
    let client: APIClient
    let unauthorized: @MainActor () async -> Void

    @State private var player: AVPlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    .accessibilityLabel(Text(label))
                    .accessibilityIdentifier("media.viewer.video")
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: target) {
            guard !Task.isCancelled else { return }
            let asset = PlayerFactory.asset(for: .media(ref: target.ref, key: target.media.key), client: client)
            let item = AVPlayerItem(asset: asset)
            if target.media.type == .animation {
                let queue = AVQueuePlayer()
                queue.isMuted = true
                looper = AVPlayerLooper(player: queue, templateItem: item)
                player = queue
            } else {
                player = PlayerFactory.player(for: item)
            }
            player?.play()
            let readiness = await PlayerFactory.readiness(of: asset)
            guard !Task.isCancelled else { return }
            if readiness == .unauthorized {
                player?.pause()
                await unauthorized()
            }
        }
        .onDisappear {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player = nil
        }
    }

    private var label: LocalizedStringKey {
        switch target.media.type {
        case .animation: "preview.kind.animation"
        case .videoNote: "preview.kind.videoNote"
        default: "preview.kind.video"
        }
    }
}
