import Foundation
import Observation
import os

/// Why the sign-in screen is showing instead of the archive.
enum EndReason: Hashable, Sendable {
    /// The stored cookie's expiry date passed; found at launch without asking the server.
    case expired
    /// The server answered 401, or the launch check said the session is gone.
    case ended
}

/// A signed-in session: what the Keychain keeps, and the client that talks with its cookie.
struct Session: Equatable, Sendable {
    let stored: StoredSession
    let client: APIClient

    static func == (lhs: Session, rhs: Session) -> Bool {
        lhs.stored == rhs.stored && lhs.client === rhs.client
    }
}

/// Why connecting or signing in did not get to the archive.
enum SessionError: Error, Equatable, Sendable {
    /// The text is not a server address or share link.
    case invalidAddress
    /// The server has no login mode configured.
    case setupRequired
    /// The server signs people in through a proxy identity header.
    case proxyAuthUnsupported
    /// A sign-in is already in flight; none is ever started twice or retried.
    case busy
    /// There is no server to sign in to yet.
    case noServer
    /// `/api/login` answered 401.
    case wrongCredentials
    /// `/auth/token` answered 401: the share link is invalid, revoked or expired.
    case invalidLink
    case api(APIError)

    var message: String {
        switch self {
        case .invalidAddress: String(localized: "session.error.invalidAddress")
        case .setupRequired: String(localized: "api.error.setupRequired")
        case .proxyAuthUnsupported: String(localized: "session.error.proxyAuthUnsupported")
        case .busy: String(localized: "session.error.busy")
        case .noServer: String(localized: "session.error.invalidAddress")
        case .wrongCredentials: String(localized: "session.error.wrongCredentials")
        case .invalidLink: String(localized: "session.error.invalidLink")
        case let .api(error): error.message
        }
    }
}

/// The one owner of session state. One install holds at most one server session, the app never creates one
/// the user did not ask for, and every way out runs the same local wipe.
@MainActor @Observable
final class SessionStore {
    enum Phase: Equatable {
        case restoring
        case connect
        case signIn(ServerAddress, prefilledToken: String?, reason: EndReason?)
        case ready(Session)
    }

    private(set) var phase: Phase = .restoring
    /// True while a sign-in request is in flight.
    private(set) var isSigningIn = false
    /// The launch check could not reach the server. The session is kept; the screen shows a banner.
    private(set) var connectionProblem: APIError?
    /// The last sign-out did not reach the server, so that server session lasts until it expires.
    private(set) var lastSignOutWasLocalOnly = false

    /// The last server address, to prefill the connect screen.
    var lastServer: String? { defaults.string(forKey: Keys.lastServer) }
    /// The last account name, to prefill the sign-in screen.
    var lastUsername: String? { defaults.string(forKey: Keys.lastUsername) }

    @ObservationIgnored private let vault: any SessionVault
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let configuration: URLSessionConfiguration
    @ObservationIgnored private let cache: URLCache
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var wipeSteps: [@MainActor () async -> Void] = []
    /// The wipe of the session that just ended; a new sign-in waits for it.
    @ObservationIgnored private var teardown: Task<Void, Never>?

    private static let log = Logger(subsystem: "io.github.geiserx.tgarchive", category: "session")

    private enum Keys {
        static let lastServer = "lastServer"
        static let lastUsername = "lastUsername"
        static let installMarker = "installMarker"
    }

    private enum Credential {
        case password(username: String, password: String)
        case token(String)
    }

    init(vault: any SessionVault = KeychainStore(), defaults: UserDefaults = .standard,
         configuration: URLSessionConfiguration = .default, cache: URLCache = APIClient.sharedCache,
         now: @escaping () -> Date = Date.init) {
        self.vault = vault
        self.defaults = defaults
        self.configuration = configuration
        self.cache = cache
        self.now = now
    }

    /// Adds a step to the local wipe that runs on sign-out and when the session ends: the media loader's
    /// purge, the downloaded files, the player.
    func addWipeStep(_ step: @escaping @MainActor () async -> Void) {
        wipeSteps.append(step)
    }

    // MARK: - Launch

    /// Loads the stored session. Never signs in on its own, so a launch never spends one of the user's
    /// server sessions.
    func restore() async {
        if !defaults.bool(forKey: Keys.installMarker) {
            await cleanUpAfterReinstall()
        }
        let stored: StoredSession?
        do {
            stored = try vault.load()
        } catch {
            Self.log.error("keychain read failed: \(String(describing: error), privacy: .public)")
            stored = nil
        }
        guard let stored else {
            phase = .connect
            return
        }
        if stored.isExpired(at: now()) {
            phase = .signIn(stored.server, prefilledToken: nil, reason: .expired)
            await wipeLocal(client: nil)
            return
        }
        let session = Session(stored: stored, client: makeClient(stored.server, cookie: stored.cookie))
        phase = .ready(session)
        await verify(session)
    }

    /// The Keychain outlives the app, so the first launch of a new install releases any session a previous
    /// install left behind.
    private func cleanUpAfterReinstall() async {
        if let leftover = try? vault.load(), leftover.cookie != nil {
            let client = makeClient(leftover.server, cookie: leftover.cookie)
            _ = await logout(using: client)
            client.urlSession.invalidateAndCancel()
        }
        try? vault.delete()
        defaults.set(true, forKey: Keys.installMarker)
    }

    /// The launch check, run after the archive is already showing.
    private func verify(_ session: Session) async {
        do {
            let check: AuthCheck = try await session.client.get(.authCheck)
            connectionProblem = nil
            if check.authRequired && !check.authenticated {
                await sessionEnded(session.client)
            }
        } catch {
            if error == .unauthorized {
                await sessionEnded(session.client)
            } else if !error.isCancellation {
                connectionProblem = error
            }
        }
    }

    // MARK: - Connect and sign in

    /// Probes the typed or pasted address and moves to the next step: sign-in, or the archive itself when the
    /// server runs in anonymous mode.
    func connect(_ text: String) async throws(SessionError) {
        guard let parsed = ServerAddress.parse(text) else { throw .invalidAddress }
        let probe = makeClient(parsed.address, cookie: nil)
        defer { probe.urlSession.finishTasksAndInvalidate() }
        let check: AuthCheck
        do {
            check = try await probe.get(.authCheck)
        } catch {
            switch error {
            case .decoding, .notFound: throw .api(.notAnArchiveServer)
            default: throw .api(error)
            }
        }
        if check.setupRequired == true { throw .setupRequired }
        if check.proxyAuth == true { throw .proxyAuthUnsupported }
        defaults.set(parsed.address.baseURL.absoluteString, forKey: Keys.lastServer)
        if !check.authRequired {
            await startAnonymous(at: parsed.address)
            return
        }
        // Leaving the archive for another sign-in ends the session it showed, so a relaunch never brings
        // back a server the user moved away from.
        await releaseCurrentSession()
        phase = .signIn(parsed.address, prefilledToken: parsed.token, reason: nil)
    }

    func signIn(username: String, password: String) async throws(SessionError) {
        try await signIn(with: .password(username: username, password: password))
    }

    /// The token is sent exactly as given: the server only needs a non-empty string.
    func signIn(token: String) async throws(SessionError) {
        try await signIn(with: .token(token))
    }

    /// Opens the server shown on the sign-in screen without a login, for a server in anonymous mode.
    func continueAnonymously() async {
        guard case let .signIn(server, _, _) = phase else { return }
        await startAnonymous(at: server)
    }

    private var signInServer: ServerAddress? {
        switch phase {
        case let .signIn(server, _, _): server
        case let .ready(session): session.stored.server
        case .restoring, .connect: nil
        }
    }

    private func signIn(with credential: Credential) async throws(SessionError) {
        guard !isSigningIn else { throw .busy }
        guard let server = signInServer else { throw .noServer }
        isSigningIn = true
        defer { isSigningIn = false }

        // A sign-in never strands a server session: release the one this install holds first.
        await releaseCurrentSession()

        let client = makeClient(server, cookie: nil)
        defer { client.urlSession.finishTasksAndInvalidate() }
        let response: LoginResponse
        let cookie: HTTPCookie?
        do {
            switch credential {
            case let .password(username, password):
                (response, cookie) = try await client.post(.login, body: LoginBody(username: username, password: password))
            case let .token(token):
                (response, cookie) = try await client.post(.tokenLogin, body: TokenBody(token: token))
            }
        } catch {
            // A 401 from a login route is about what the user typed, never about a session.
            guard error == .unauthorized else { throw .api(error) }
            switch credential {
            case .password: throw .wrongCredentials
            case .token: throw .invalidLink
            }
        }

        guard let cookie else {
            // `/api/login` on a server in anonymous mode answers 200 with a message and sets no cookie.
            if response.message != nil {
                await startAnonymous(at: server)
                return
            }
            throw .api(.decoding("no session cookie in the sign-in answer"))
        }

        let signedIn = makeClient(server, cookie: cookie.value)
        let check: AuthCheck
        do {
            check = try await signedIn.get(.authCheck)
        } catch {
            _ = await logout(using: signedIn)
            signedIn.urlSession.invalidateAndCancel()
            throw .api(error)
        }
        guard check.authenticated else {
            signedIn.urlSession.invalidateAndCancel()
            throw .api(.unauthorized)
        }

        let stored = StoredSession(
            server: server,
            cookie: cookie.value,
            cookieExpires: cookie.expiresDate,
            username: check.username ?? response.username,
            role: StoredSession.Role(serverRole: check.role ?? response.role),
            noDownload: check.noDownload ?? response.noDownload ?? false
        )
        save(stored)
        if case let .password(username, _) = credential {
            defaults.set(username, forKey: Keys.lastUsername)
        }
        connectionProblem = nil
        phase = .ready(Session(stored: stored, client: signedIn))
    }

    private func startAnonymous(at server: ServerAddress) async {
        await releaseCurrentSession()
        let stored = StoredSession(server: server, cookie: nil, cookieExpires: nil, username: nil,
                                   role: .anonymous, noDownload: false)
        save(stored)
        connectionProblem = nil
        phase = .ready(Session(stored: stored, client: makeClient(server, cookie: nil)))
    }

    /// Ends the session this install holds, on the server and locally, without changing the phase.
    private func releaseCurrentSession() async {
        await teardown?.value
        var client: APIClient?
        var stored: StoredSession?
        if case let .ready(session) = phase {
            client = session.client
            stored = session.stored
            // The old session is gone from here on, whether or not the new sign-in works.
            phase = .signIn(session.stored.server, prefilledToken: nil, reason: nil)
        } else {
            stored = try? vault.load()
        }
        guard let stored else { return }
        if stored.cookie != nil {
            let logoutClient = client ?? makeClient(stored.server, cookie: stored.cookie)
            lastSignOutWasLocalOnly = !(await logout(using: logoutClient))
            client = logoutClient
        }
        await wipeLocal(client: client)
    }

    // MARK: - Sign out and session end

    /// Settings' Sign out (Disconnect on an anonymous server): tells the server, then wipes everything local.
    /// Offline is fine: the wipe runs anyway, and the server session lasts until it expires.
    func signOut() async {
        guard case let .ready(session) = phase else { return }
        let stored = session.stored
        phase = stored.role == .anonymous
            ? .connect
            : .signIn(stored.server, prefilledToken: nil, reason: nil)
        deleteStored()
        let finished = Task {
            if stored.cookie != nil {
                self.lastSignOutWasLocalOnly = !(await self.logout(using: session.client))
            }
            await self.wipeLocal(client: session.client)
        }
        teardown = finished
        await finished.value
    }

    /// The server ended the session: a 401 from any route other than sign-in, or the launch check. Runs the
    /// sign-out wipe without the server call. A burst of 401s from parallel loads makes one transition, and a
    /// late 401 from an older session's client is ignored.
    func sessionEnded(_ client: APIClient? = nil) async {
        guard case let .ready(session) = phase else { return }
        if let client, client !== session.client { return }
        phase = .signIn(session.stored.server, prefilledToken: nil, reason: .ended)
        deleteStored()
        let finished = Task { await self.wipeLocal(client: session.client) }
        teardown = finished
        await finished.value
    }

    // MARK: - Helpers

    private func makeClient(_ server: ServerAddress, cookie: String?) -> APIClient {
        APIClient(server: server, cookie: cookie, configuration: configuration, cache: cache)
    }

    /// `POST /api/logout` with a 5 s timeout. True when the server answered at all.
    private func logout(using client: APIClient) async -> Bool {
        do {
            let _: (value: LoginResponse, setCookie: HTTPCookie?) = try await client.post(.logout, body: [String: String]())
            return true
        } catch {
            if case .transport = error { return false }
            return true
        }
    }

    /// The native form of the server's `Clear-Site-Data: "cache"`, plus everything else the session left.
    private func wipeLocal(client: APIClient?) async {
        deleteStored()
        cache.removeAllCachedResponses()
        // Never `invalidateAndCancel()` here: views still holding this client would crash on their next request.
        client?.end()
        for step in wipeSteps {
            await step()
        }
    }

    private func save(_ stored: StoredSession) {
        do {
            try vault.save(stored)
        } catch {
            Self.log.error("keychain write failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func deleteStored() {
        do {
            try vault.delete()
        } catch {
            Self.log.error("keychain delete failed: \(String(describing: error), privacy: .public)")
        }
    }
}
