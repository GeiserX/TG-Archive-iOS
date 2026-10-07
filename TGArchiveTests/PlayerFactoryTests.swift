import AVFoundation
import Foundation
import Testing
@testable import TGArchive

/// The 1.5 s Ogg/Opus tone in the test bundle, made the way Telegram makes voice notes.
func voiceNoteFixture() throws -> URL {
    final class BundleToken {}
    return try #require(Bundle(for: BundleToken.self).url(forResource: "voice-note", withExtension: "ogg"))
}

@MainActor
@Suite("Player factory")
struct PlayerFactoryTests {
    private func client(_ address: String, cookie: String?) throws -> APIClient {
        let server = try #require(ServerAddress.parse(address)).address
        return APIClient(server: server, cookie: cookie, configuration: .ephemeral)
    }

    @Test("The cookie carries the session for the server's host and path /, not Secure over plain http")
    func cookieOverHTTP() throws {
        let cookie = try #require(PlayerFactory.cookie(for: client("http://192.168.1.20:8000/archive", cookie: "abc.123")))
        #expect(cookie.name == "viewer_auth")
        #expect(cookie.value == "abc.123")
        #expect(cookie.domain == "192.168.1.20")
        #expect(cookie.path == "/")
        #expect(!cookie.isSecure)
    }

    @Test("Over https the cookie is Secure")
    func cookieOverHTTPS() throws {
        let cookie = try #require(PlayerFactory.cookie(for: client("https://archive.example.org", cookie: "v")))
        #expect(cookie.domain == "archive.example.org")
        #expect(cookie.isSecure)
    }

    @Test("An anonymous server gets no cookie and no asset options")
    func anonymous() throws {
        let anonymous = try client("https://archive.example.org", cookie: nil)
        #expect(PlayerFactory.cookie(for: anonymous) == nil)
        #expect(PlayerFactory.options(for: anonymous).isEmpty)
    }

    @Test("The asset asks for the file under the server's path prefix, with the cookie in the public option")
    func asset() throws {
        let client = try client("https://archive.example.org/tg", cookie: "v")
        let asset = PlayerFactory.asset(for: .media(ref: "chat-ref", key: "203_video"), client: client)
        #expect(asset.url.absoluteString == "https://archive.example.org/tg/media/chat-ref/203_video")
        let cookies = try #require(PlayerFactory.options(for: client)[AVURLAssetHTTPCookiesKey] as? [HTTPCookie])
        #expect(cookies.map(\.value) == ["v"])
    }

    /// Telegram voice notes are Opus in an Ogg container; the fixture is a 1.5 s tone made the same way. The
    /// decode runs through an asset reader, so it needs no audio output device.
    @Test("AVFoundation on this OS decodes an Ogg/Opus voice note")
    func oggOpusDecodes() async throws {
        let asset = AVURLAsset(url: try voiceNoteFixture())
        #expect(try await asset.load(.isPlayable))
        #expect(abs(try await asset.load(.duration).seconds - 1.5) < 0.1)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        reader.add(output)
        #expect(reader.startReading())
        var frames = 0
        while let buffer = output.copyNextSampleBuffer() {
            frames += CMSampleBufferGetNumSamples(buffer)
        }
        #expect(reader.status == .completed)
        let seconds = Double(frames) / 48_000
        #expect(abs(seconds - 1.5) < 0.1, "decoded \(frames) frames")
    }
}

@MainActor
@Suite("In-place playback and sharing")
struct AudioPlaybackTests {
    @Test("A voice note AVFoundation reads is playable, with its length")
    func playable() async throws {
        let readiness = await PlayerFactory.readiness(of: AVURLAsset(url: try voiceNoteFixture()))
        guard case let .playable(duration) = readiness else {
            Issue.record("expected playable, got \(readiness)")
            return
        }
        #expect(abs((duration ?? 0) - 1.5) < 0.1)
    }

    @Test("Bytes no reader understands are unsupported, not a failed load")
    func unsupported() async throws {
        let url = URL.temporaryDirectory.appending(path: "tgarchive-noise-\(UUID().uuidString).ogg")
        try Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(await PlayerFactory.readiness(of: AVURLAsset(url: url)) == .unsupported)
    }

    @Test("Load errors: AVFoundation's own mean unplayable, network ones a failed load, and 401 the session's end")
    func readinessForErrors() {
        let damaged = NSError(domain: AVFoundationErrorDomain, code: -11849)
        let noDecoder = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.decoderNotFound.rawValue)
        let offline = NSError(domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue)
        let wrappedOffline = NSError(domain: AVFoundationErrorDomain, code: AVError.Code.unknown.rawValue,
                                     userInfo: [NSUnderlyingErrorKey: offline])
        let unauthorized = NSError(domain: NSURLErrorDomain, code: URLError.userAuthenticationRequired.rawValue)
        let other = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileReadUnknown.rawValue)
        #expect(PlayerFactory.readiness(for: damaged) == .unsupported)
        #expect(PlayerFactory.readiness(for: noDecoder) == .unsupported)
        #expect(PlayerFactory.readiness(for: offline) == .failed)
        #expect(PlayerFactory.readiness(for: wrappedOffline) == .failed)
        #expect(PlayerFactory.readiness(for: unauthorized) == .unauthorized)
        #expect(PlayerFactory.readiness(for: other) == .failed)
    }

    @Test("A shared file keeps its own type, from the MIME type, else the name, else plain data")
    func shareType() throws {
        let photo = try media(#"{"id": "1_photo", "type": "photo", "mime_type": "image/jpeg"}"#)
        let video = try media(#"{"id": "2_video", "type": "video", "mime_type": "video/mp4"}"#)
        let named = try media(#"{"id": "3_document", "type": "document", "file_name": "1700_plan.pdf"}"#)
        let bare = try media(#"{"id": "4_document", "type": "document"}"#)
        #expect(SharedMediaFile.contentType(of: photo) == .jpeg)
        #expect(SharedMediaFile.contentType(of: video) == .mpeg4Movie)
        #expect(SharedMediaFile.contentType(of: named) == .pdf)
        #expect(SharedMediaFile.contentType(of: bare) == .data)
    }

    @Test("Two files of one chat are two viewer targets")
    func targetIdentity() throws {
        let first = MediaTarget(ref: "r", messageID: 1, media: try media(#"{"id": "1_photo", "type": "photo"}"#))
        let second = MediaTarget(ref: "r", messageID: 2, media: try media(#"{"id": "2_photo", "type": "photo"}"#))
        #expect(first.id == "r/1_photo")
        #expect(first.id != second.id)
    }

    private func media(_ json: String) throws -> MessageMedia {
        try ArchiveDecoder.decode(MessageMedia.self, from: Data(json.utf8))
    }
}

/// Loads from the demo server through AVFoundation's own HTTP stack: the cookie reaches it, and a video and
/// an Ogg voice note open as playable assets. It checks the assets, not the sound, so it needs no audio device.
@MainActor
@Suite("Live playback", .serialized, .enabled(if: LiveServer.baseURL != nil, "TGARCHIVE_DEMO_URL is not set"))
struct LivePlaybackTests {
    @Test("A video and an Ogg voice note open with the session cookie; without it the server refuses them")
    func streams() async throws {
        let baseURL = try #require(LiveServer.baseURL)
        let suite = "tgarchive.live.player.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "installMarker")
        let cache = URLCache(memoryCapacity: 4 * 1024 * 1024, diskCapacity: 0, directory: nil)
        let store = SessionStore(vault: MemoryVault(), defaults: defaults, configuration: .ephemeral, cache: cache)
        try await store.connect(baseURL)
        try await store.signIn(username: LiveServer.username, password: LiveServer.password)
        guard case let .ready(session) = store.phase else {
            Issue.record("not signed in: \(store.phase)")
            return
        }

        // The first downloaded voice note and video the master can see.
        var voice: (ref: String, media: MessageMedia)?
        var video: (ref: String, media: MessageMedia)?
        let chats: ChatsPage = try await session.client.get(.chats(limit: 100))
        for chat in chats.chats where voice == nil || video == nil {
            let page: MessagePage = try await session.client.get(.messages(ref: chat.ref, limit: 200))
            for media in page.messages.compactMap(\.media) where media.url != nil {
                if media.type == .voice, voice == nil { voice = (chat.ref, media) }
                if media.type == .video, video == nil { video = (chat.ref, media) }
            }
        }
        let voiceNote = try #require(voice, "the demo archive has a downloaded voice note")
        let videoFile = try #require(video, "the demo archive has a downloaded video")
        #expect(voiceNote.media.mimeType == "audio/ogg")

        let videoAsset = PlayerFactory.asset(for: .media(ref: videoFile.ref, key: videoFile.media.key),
                                             client: session.client)
        #expect(try await videoAsset.load(.isPlayable))
        #expect(try await !videoAsset.loadTracks(withMediaType: .video).isEmpty)

        let voiceAsset = PlayerFactory.asset(for: .media(ref: voiceNote.ref, key: voiceNote.media.key),
                                             client: session.client)
        #expect(try await voiceAsset.load(.isPlayable))
        let duration = try await voiceAsset.load(.duration).seconds
        #expect(abs(duration - (voiceNote.media.duration ?? 0)) < 1, "duration \(duration)")

        // Negative control: the same file without the cookie is refused, so the cookie above did the work.
        let stranger = APIClient(server: session.stored.server, cookie: nil, configuration: .ephemeral, cache: cache)
        let refused = PlayerFactory.asset(for: .media(ref: voiceNote.ref, key: voiceNote.media.key), client: stranger)
        let refusedPlayable = try? await refused.load(.isPlayable)
        #expect(refusedPlayable != true)
        // A refused file is a failed load, never "this device can't play it".
        // A refused file reaches AVFoundation as a 401: the session's end, never "this device can't play it".
        #expect(await PlayerFactory.readiness(of: PlayerFactory.asset(
            for: .media(ref: voiceNote.ref, key: voiceNote.media.key), client: stranger)) == .unauthorized)

        // The cell's model says the file failed and hands the 401 on. It never plays here: on some build
        // machines the simulator's first audio output stalls for minutes.
        let refusedPlayback = AudioPlayback()
        let ended = Flag()
        refusedPlayback.toggle(.media(ref: voiceNote.ref, key: voiceNote.media.key), client: stranger,
                               knownDuration: nil) { ended.isSet = true }
        #expect(refusedPlayback.state == .loading)
        try await waitFor { refusedPlayback.state != .loading }
        #expect(refusedPlayback.state == .failed)
        #expect(ended.isSet)

        await store.signOut()
    }
}

/// Polls a condition on the main actor for up to `timeout`.
@MainActor
func waitFor(timeout: Duration = .seconds(15), _ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition(), clock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
}

@MainActor
final class Flag {
    var isSet = false
}
