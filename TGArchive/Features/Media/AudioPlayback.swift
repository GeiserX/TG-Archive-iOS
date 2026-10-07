import AVFoundation
import Observation

/// Plays one voice note or audio file inside its cell: play and pause, the elapsed time and the progress.
/// Only one plays at a time; starting one pauses the other, and the media viewer pauses it too.
///
/// Before playing it asks AVFoundation whether it can play the file, so a file the device cannot decode says
/// so instead of a silent button, and a 401 ends the session like any other media route.
@MainActor @Observable
final class AudioPlayback {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case paused
        /// AVFoundation on this device cannot play the file.
        case unsupported
        /// The file did not load: offline, a server error, or a session that ended.
        case failed
    }

    private(set) var state: State = .idle
    /// Seconds played.
    private(set) var elapsed: Double = 0
    /// 0 to 1.
    private(set) var progress: Double = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var duration: Double = 0

    private static weak var current: AudioPlayback?

    /// Pauses whatever plays, for the media viewer.
    static func pauseCurrent() {
        current?.pause()
    }

    var isActive: Bool { state == .loading || state == .playing }

    /// Play from the start or where it paused, or pause. `unauthorized` runs when the server answers 401.
    func toggle(_ endpoint: Endpoint, client: APIClient, knownDuration: Double?,
                unauthorized: @escaping @MainActor () async -> Void = {}) {
        switch state {
        case .playing, .loading:
            pause()
        case .paused:
            resume()
        case .idle, .unsupported, .failed:
            start(endpoint, client: client, knownDuration: knownDuration, unauthorized: unauthorized)
        }
    }

    func pause() {
        loading?.cancel()
        loading = nil
        player?.pause()
        if state == .playing || state == .loading { state = player == nil ? .idle : .paused }
    }

    /// Stops and lets go of the player, for a cell that scrolled away or a session that ended.
    func stop() {
        loading?.cancel()
        loading = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        player = nil
        if state != .unsupported && state != .failed { state = .idle }
        elapsed = 0
        progress = 0
        if Self.current === self { Self.current = nil }
    }

    private func start(_ endpoint: Endpoint, client: APIClient, knownDuration: Double?,
                       unauthorized: @escaping @MainActor () async -> Void) {
        stop()
        Self.takeOver(self)
        state = .loading
        let asset = PlayerFactory.asset(for: endpoint, client: client)
        loading = Task { [weak self] in
            let readiness = await PlayerFactory.readiness(of: asset)
            guard let self, !Task.isCancelled else { return }
            switch readiness {
            case .unsupported:
                self.state = .unsupported
            case .failed:
                self.state = .failed
            case .unauthorized:
                self.state = .failed
                await unauthorized()
            case let .playable(seconds):
                self.duration = seconds ?? knownDuration ?? 0
                self.play(asset)
            }
        }
    }

    private func play(_ asset: AVURLAsset) {
        let player = PlayerFactory.player(for: AVPlayerItem(asset: asset))
        player.actionAtItemEnd = .pause
        self.player = player
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
        state = .playing
        player.play()
    }

    private func resume() {
        guard let player else { return }
        Self.takeOver(self)
        state = .playing
        player.play()
    }

    private func tick(_ time: CMTime) {
        guard let player else { return }
        let seconds = time.seconds.isFinite ? max(time.seconds, 0) : 0
        elapsed = seconds
        progress = duration > 0 ? min(seconds / duration, 1) : 0
        // The item ended: back to the start, ready to play again.
        if state == .playing, player.timeControlStatus == .paused, duration > 0, seconds >= duration - 0.25 {
            player.seek(to: .zero)
            state = .paused
            elapsed = 0
            progress = 0
        }
    }

    private static func takeOver(_ playback: AudioPlayback) {
        if let current, current !== playback { current.pause() }
        current = playback
    }
}
