import Foundation
import ImageIO
import Synchronization
import UIKit

/// Why an image or a file did not load. Each case has its own tile, so none of them is shown as an error.
enum MediaFailure: Error, Equatable, Sendable {
    /// 403: downloads are off for this login. The session stays.
    case downloadsOff
    /// 404: no such file or thumbnail (a video without server-side ffmpeg, an animated sticker), or a chat
    /// this login no longer sees.
    case missing
    /// 401: the session ended on the server. `SessionStore.sessionEnded(_:)` has been told.
    case sessionEnded
    /// The bytes are not an image ImageIO can decode.
    case undecodable
    /// Anything else: offline, a server error, a cancelled load.
    case failed(APIError)

    init(_ error: APIError) {
        switch error {
        case .forbidden: self = .downloadsOff
        case .notFound: self = .missing
        case .unauthorized: self = .sessionEnded
        default: self = .failed(error)
        }
    }

    var isCancellation: Bool { self == .failed(.transport(.cancelled)) }
}

/// Loads and decodes the images of one session: avatars, thumbnails and sticker files.
///
/// Every load asks the server. The answers carry `Cache-Control: private, no-cache` and an `ETag`, so the
/// session's `URLCache` revalidates the stored copy with `If-None-Match` and the server runs its login and
/// chat checks each time; a `304` reuses the stored bytes. The decoded image is kept in memory under the
/// URL, the size and the `ETag`, which only spares the decode. Requests for the same image while one is in
/// flight share it, and a load nobody waits for any more is cancelled.
actor MediaLoader {
    typealias SessionEnded = @Sendable @MainActor (APIClient) async -> Void

    nonisolated let client: APIClient
    nonisolated let files: FileStore
    private let sessionEnded: SessionEnded
    private let images = NSCache<NSString, UIImage>()
    private var inFlight: [String: Flight] = [:]

    init(client: APIClient, files: FileStore = .shared, sessionEnded: @escaping SessionEnded) {
        self.client = client
        self.files = files
        self.sessionEnded = sessionEnded
        images.countLimit = 300
    }

    /// The image at a media route, decoded to at most `maxPixelSize` pixels on its long side.
    func image(for endpoint: Endpoint, maxPixelSize: Int) async throws(MediaFailure) -> UIImage {
        let request = client.request(for: endpoint)
        let key = "\(request.url?.absoluteString ?? "")#\(maxPixelSize)"
        let flight: Flight
        if let existing = inFlight[key], !existing.task.isCancelled {
            flight = existing
        } else {
            let session = client.urlSession
            // Isolated to this actor; the fetch and the decode hop off it.
            let task = Task<UIImage, any Error> {
                let (data, etag) = try await Self.fetch(request, session: session)
                let cacheKey = etag.map { "\(key)#\($0)" as NSString }
                if let cacheKey, let image = self.images.object(forKey: cacheKey) { return image }
                let image = try await Self.decode(data, maxPixelSize: maxPixelSize)
                if let cacheKey { self.images.setObject(image, forKey: cacheKey) }
                return image
            }
            flight = Flight(task: task)
            inFlight[key] = flight
        }
        flight.join()
        let result = await withTaskCancellationHandler {
            await flight.task.result
        } onCancel: {
            flight.leave()
        }
        if !Task.isCancelled { flight.leave() }
        if inFlight[key] === flight, flight.isFinishedOrAbandoned { inFlight[key] = nil }
        switch result {
        case let .success(image):
            return image
        case let .failure(error):
            throw await failure(from: error)
        }
    }

    /// Downloads an original file for Quick Look, into `tmp/Media/<ref>/<key>/<file name>`.
    func file(ref: String, key: String, fileName: String?) async throws(MediaFailure) -> URL {
        do {
            return try await files.download(ref: ref, key: key, fileName: fileName, client: client)
        } catch {
            throw await failure(from: error)
        }
    }

    /// Drops every decoded image and cancels every load. Part of the sign-out wipe.
    func purge() {
        for flight in inFlight.values { flight.task.cancel() }
        inFlight = [:]
        images.removeAllObjects()
    }

    /// Maps a load error, and tells the session store once a 401 arrives.
    private func failure(from error: any Error) async -> MediaFailure {
        let mapped: MediaFailure
        switch error {
        case let error as MediaFailure: mapped = error
        case let error as APIError: mapped = MediaFailure(error)
        case is CancellationError: mapped = .failed(.transport(.cancelled))
        default: mapped = .failed(APIError.from(transport: error))
        }
        if mapped == .sessionEnded { await sessionEnded(client) }
        return mapped
    }

    /// The bytes of a media route and the `ETag` they were served with, through the session's HTTP cache.
    @concurrent
    private static func fetch(_ request: URLRequest, session: URLSession) async throws -> (Data, String?) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.from(transport: error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.from(status: http.statusCode, body: data)
        }
        return (data, http.value(forHTTPHeaderField: "ETag"))
    }

    /// Decodes straight to the size the screen needs, off the main actor.
    @concurrent
    static func decode(_ data: Data, maxPixelSize: Int) async throws -> UIImage {
        try Task.checkCancellation()
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw MediaFailure.undecodable
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw MediaFailure.undecodable
        }
        return UIImage(cgImage: image)
    }
}

/// One shared load and how many views wait for it.
private final class Flight: Sendable {
    let task: Task<UIImage, any Error>
    private let state = Mutex((waiters: 0, joined: false))

    init(task: Task<UIImage, any Error>) { self.task = task }

    func join() {
        state.withLock {
            $0.waiters += 1
            $0.joined = true
        }
    }

    /// The last waiter to leave before the load ends cancels it.
    func leave() {
        let abandoned = state.withLock {
            $0.waiters -= 1
            return $0.waiters <= 0
        }
        if abandoned { task.cancel() }
    }

    var isFinishedOrAbandoned: Bool {
        state.withLock { $0.joined && $0.waiters <= 0 }
    }
}

extension MediaLoader {
    /// The loader of the signed-in session, made on first use. Its wipe joins the session store's local
    /// wipe, so sign-out and a session the server ended drop every decoded image and downloaded file.
    @MainActor
    static func current(for session: Session, in store: SessionStore) -> MediaLoader {
        Registry.loader(for: session, in: store)
    }

    @MainActor
    private enum Registry {
        static var loader: MediaLoader?
        static var wiredStores: [ObjectIdentifier] = []

        static func loader(for session: Session, in store: SessionStore) -> MediaLoader {
            if !wiredStores.contains(ObjectIdentifier(store)) {
                wiredStores.append(ObjectIdentifier(store))
                store.addWipeStep { await Registry.wipe() }
            }
            if let loader, loader.client === session.client { return loader }
            let made = MediaLoader(client: session.client) { [weak store] client in
                await store?.sessionEnded(client)
            }
            loader = made
            return made
        }

        static func wipe() async {
            let old = loader
            loader = nil
            await old?.purge()
            FileStore.shared.wipe()
        }
    }
}
