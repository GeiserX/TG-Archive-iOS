import AVFoundation

/// Builds the players for the archive's videos, round videos, voice notes and audio files.
///
/// AVFoundation fetches media with its own HTTP stack, not the session's `URLSession`, so the session cookie
/// goes in through the public `AVURLAssetHTTPCookiesKey`: an `HTTPCookie` built from the stored value for the
/// server's host, path `/`, and `Secure` only when the server is https. The private header-fields option is
/// never used. The server answers byte ranges, which AVFoundation needs to stream a file.
@MainActor
enum PlayerFactory {
    /// The session cookie in the form AVFoundation takes, or nil for an anonymous server.
    nonisolated static func cookie(for client: APIClient) -> HTTPCookie? {
        let base = client.server.baseURL
        guard let value = client.cookie, !value.isEmpty, let host = base.host(percentEncoded: false) else {
            return nil
        }
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: APIClient.cookieName,
            .value: value,
            .domain: host,
            .path: "/",
        ]
        if base.scheme?.lowercased() == "https" { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }

    /// The asset options: the session cookie, when there is one.
    nonisolated static func options(for client: APIClient) -> [String: Any] {
        guard let cookie = cookie(for: client) else { return [:] }
        return [AVURLAssetHTTPCookiesKey: [cookie]]
    }

    /// The file of a media route as an asset, its URL built under the server's path prefix.
    static func asset(for endpoint: Endpoint, client: APIClient) -> AVURLAsset {
        AVURLAsset(url: endpoint.url(base: client.server.baseURL), options: options(for: client))
    }

    /// A player for a media route. Playback follows the media volume, not the ring/silent switch.
    static func player(for endpoint: Endpoint, client: APIClient) -> AVPlayer {
        player(for: AVPlayerItem(asset: asset(for: endpoint, client: client)))
    }

    /// A player for an item made from one of these assets.
    static func player(for item: AVPlayerItem) -> AVPlayer {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        return AVPlayer(playerItem: item)
    }

    /// What AVFoundation makes of a file before it plays.
    enum Readiness: Equatable, Sendable {
        case playable(duration: Double?)
        /// AVFoundation cannot read or decode the file on this device.
        case unsupported
        /// The server answered 401: the session ended.
        case unauthorized
        /// It did not load: offline, refused, or a server error.
        case failed
    }

    /// Loads what playback needs to know. The asset keeps what it loaded, so a player made from the same asset
    /// does not fetch it again.
    nonisolated static func readiness(of asset: AVURLAsset) async -> Readiness {
        do {
            let (playable, duration) = try await asset.load(.isPlayable, .duration)
            guard playable else { return .unsupported }
            let seconds = duration.seconds
            return .playable(duration: seconds.isFinite && seconds > 0 ? seconds : nil)
        } catch {
            return readiness(for: error)
        }
    }

    /// A load error read as a readiness: AVFoundation's own errors mean it cannot play the file (no reader, no
    /// decoder, or damaged), unless a network error lies under them; a 401 reaches AVFoundation as
    /// `userAuthenticationRequired`.
    nonisolated static func readiness(for error: any Error) -> Readiness {
        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            return error.code == URLError.userAuthenticationRequired.rawValue ? .unauthorized : .failed
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSURLErrorDomain {
            return readiness(for: underlying)
        }
        return error.domain == AVFoundationErrorDomain ? .unsupported : .failed
    }
}
