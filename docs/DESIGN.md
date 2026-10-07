# TG Archive for iOS: design for the read-only v1

This is the one design the implementation follows. It fixes the product, the screens, the Swift types, the session rules, the demo server, the App Review plan, what v1 leaves out, and the order of work with file ownership.

## 1. Product

TG Archive is a native SwiftUI, iPhone-only, read-only client for one self-hosted Telegram-Archive server at a time. You enter your server's address, sign in with a viewer account or a share link (or nothing, when the server runs in anonymous mode), and read your archived chats: the chat list with previews, forum topics, message threads with photos, videos, documents, voice notes and their transcripts, locations, contacts, polls, replies, forwards, reactions, and the marks the archive keeps for messages edited or deleted in Telegram. You can search every message and open the chat at the hit. The app talks only to the server's [documented JSON API](https://github.com/GeiserX/Telegram-Archive/blob/main/docs/reference/api.md). It never talks to Telegram, never writes anything, and sends nothing to us.

Four server facts shape everything below.

- The server is the user's own. There are no API keys. Access is a session cookie from a password login or a share link, or anonymous mode ([logins, viewer accounts and share links](https://github.com/GeiserX/Telegram-Archive/blob/main/docs/viewer/access.md)).
- Each user holds at most 10 server sessions; the 11th login ends the oldest. The app therefore holds exactly one session per install and ends it cleanly.
- Login and share-link login share one rate limit: 15 attempts per client IP in 5 minutes.
- Media answers carry `ETag` and `Cache-Control: private, no-cache`: the client may keep a copy but must revalidate every reuse, so the server's access checks run each time.

### Naming and disclosure rules

- The app is called **TG Archive** everywhere: display name, App Store name, About screen. "Telegram" is never part of the app name, subtitle, keywords, bundle id or icon.
- The icon is ours: no paper plane, no Telegram blue, no bubble that copies Telegram's. Message bubbles use our own accent colour and shape.
- The word "Telegram" appears in exactly two places: the store description's last paragraph and the About screen, both with this text: "TG Archive is unofficial and not affiliated with Telegram. It reads backups made by Telegram-Archive, an open source server you run yourself, which uses the Telegram API." The server project's name, "Telegram-Archive", is used as the name of that project and nothing else.
- Nothing committed to this public repo names a private server, hostname, person or deployment. Docs say "your server" or "the demo server". Review credentials and the demo URL live only in App Store Connect.

## 2. Screens and the routes each one uses

Three tabs (Chats, Search, Settings) plus the screens pushed or presented from them. Every list pages from the server; nothing is mirrored locally beyond the HTTP cache.

| Screen | What it does | Routes |
|---|---|---|
| **ConnectView** (first run, and after sign-out) | One field for the server address, and a `PasteButton` labelled "Paste share link" (no paste-permission prompt). Two sentences say what a Telegram-Archive server is, with a link to its docs. It probes the address and routes to the right next step. | `GET /api/auth/check` |
| **SignInView** | Segmented control, Account or Share link. Account posts username and password. Share link posts the token, prefilled when a link was pasted. Shows the server host so the user knows where the password goes. | `POST /api/login`, `POST /auth/token`, `GET /api/auth/check` |
| **ChatListView** (tab Chats) | Avatar, title, one-line preview, relative date. `.searchable` filters titles on the server. A toolbar menu picks a folder when the server has folders. An "Archived (n)" row at the top opens the same list with `archived=true`. Pull to refresh. Forum chats push TopicListView; every other chat pushes ChatView. | `GET /api/chats?limit=50&offset=&search=&archived=false&folder_id=`, `GET /api/folders`, `GET /api/archived/count`, `GET /media/avatar/{ref}` |
| **TopicListView** | The topics of a forum chat: emoji or coloured glyph, title, message count, last date. Pinned first, closed topics get a lock, hidden topics are skipped. Tapping opens ChatView with `topic_id`. | `GET /api/chats/{ref}/topics` |
| **ChatView** | The thread, newest at the bottom, with day headers. Older pages load when you scroll up. Opened from Search, it starts at the hit and also pages newer messages. Every message kind renders natively (section 3.6). | `GET /api/chats/{ref}/messages?limit=50&before_date=&before_id=&topic_id=`, `...?before_id=`, `...?after_id=`, `GET /media/thumb/400/{ref}/{key}`, `GET /media/avatar/{ref}/{message_id}` |
| **MediaViewer** (full-screen cover) | Photo: zoom and pan. Video and round video: AVKit `VideoPlayer`. Document: download to a temp file, then Quick Look. `ShareLink` only when downloads are allowed for this login. | `GET /media/{ref}/{key}`, `GET /media/thumb/400/{ref}/{key}` |
| **SearchView** (tab Search) | Word-prefix search across every chat the login sees. Each row: chat avatar and title, sender, date, snippet, topic title for forum hits, a "Deleted in Telegram" tag when `is_deleted`. Tapping opens ChatView anchored at the message. | `GET /api/search/messages?q=&limit=20&offset=` |
| **SettingsView** (tab Settings) and **AboutView** | Server host; signed in as (username and role: Owner, Viewer, Share link "label", or Open server); "Downloads are off for this login" when `no_download`; an Archive section (chats, messages, media files, last backup) when `show_stats`; Sign out with confirmation; Clear cache; About with the disclaimer, version, and links to the privacy policy, the source code and the GPL text. | `GET /api/stats`, `POST /api/logout` |

Stage 7 note: a document downloads in its cell and opens straight in Quick Look, which carries its own share button, so the full-screen viewer holds photos and videos only; voice notes and audio files play inside their cell. The share button downloads the original file only when a share target asks for it.

Stage 4 note: `PasteButton`'s title is fixed by the system ("Paste"), so its row on ConnectView reads "Have a share link?"; SignInView's "Other Server" button returns to ConnectView through view state in `RootView`, since changing server before signing in changes no session.

### Shared chats and the preview, as the API defines them

- A chat row's `ref` is opaque; the app never sees or needs a Telegram chat id. A channel or supergroup that several of the archive's accounts hold is listed once, under one ref, with `accounts` listing them; a private chat is per account. The app shows what the list returns and never deduplicates or merges rows itself.
- `preview` is the chat's newest message that was not deleted in Telegram, read through the same restrictions as the chat's messages, or `null`. The row's second line is built from it: `sender` is `You`, a first name, or `null` (channels, the other side of a private chat, service rows); `text` is the one-line text; `kind` is `text`, `service`, `poll`, a media type, or `message`. When `text` is `null` the line is a localized label for `kind` with an SF Symbol ("Photo", "Voice message", "Location", ...). A service row with `text` null and `action` set is worded from `action` and `action_title` with the same table the thread uses (section 3.6). The app never fetches a message to build a preview.
- Stage 5 note: a service row's `sender` is always `null` in the preview, so the preview words an `action` without the sender ("Group photo changed"), while the thread prefixes the sender's name. `ServiceText` in `Features/Chats/PreviewText.swift` holds both forms of the table for the thread to reuse.
- `GET /api/chats?archived` omitted returns every chat, archived included. The list sends `archived=false` and shows the "Archived (n)" row from `/api/archived/count`, so archived chats are reachable but out of the way, as in the web viewer.
- Display title: `title`, else `first_name` plus `last_name`, else `@username`, else "Deleted account".

## 3. Architecture

### 3.1 Targets and settings

- XcodeGen `project.yml` is the single source of truth; the `.xcodeproj` is generated and never committed.
- App target `TGArchive`: iOS 18.0, `SWIFT_VERSION "6.0"` (language mode 6, strict concurrency), `TARGETED_DEVICE_FAMILY "1"` set on every target, portrait plus landscape, `DEVELOPMENT_TEAM 624WUVM8B4`, Release signs manually with the profile "TG Archive App Store". Bundle id `io.github.geiserx.tgarchive`; tests `io.github.geiserx.tgarchive.tests` and `.uitests`.
- Test targets `TGArchiveTests` (Swift Testing, fixtures as resources) and `TGArchiveUITests` (XCTest, run against the demo server).
- Frameworks: SwiftUI, Observation, Foundation, Security, ImageIO, AVKit, QuickLook, MapKit. **No third-party packages.** WebP thumbnails and static stickers decode through ImageIO. The only package worth a debate was Lottie for animated `.tgs` stickers, and those are cut from v1.
- Info.plist: `CFBundleDisplayName` "TG Archive"; `ITSAppUsesNonExemptEncryption` false; `NSAppTransportSecurity { NSAllowsLocalNetworking: true }` and nothing else, never `NSAllowsArbitraryLoads`; `NSLocalNetworkUsageDescription` (localized) "TG Archive connects to your archive server when you enter an address on your local network."; single scene; no background modes, URL schemes or associated domains.
- `PrivacyInfo.xcprivacy`: `NSPrivacyTracking` false, no collected data types, Required Reason APIs: `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` only. The code uses no file-timestamp, boot-time or disk-space APIs, and a CI script greps for them with a positive control.
- Strings: `en.lproj` and `es.lproj`, `Localizable.strings` and `InfoPlist.strings` (`LOCALIZATION_PREFERS_STRING_CATALOGS NO`).

### 3.2 Source layout and the concrete types

```
TGArchive/
  App/        TGArchiveApp.swift  RootView.swift  MainTabView.swift
  API/        APIClient.swift  Endpoint.swift  APIError.swift  ArchiveDecoder.swift
  API/Models/ AuthCheck.swift  LoginResponse.swift  Chat.swift  Folder.swift  Topic.swift
              Message.swift  SearchResult.swift  ArchiveStats.swift
  Session/    SessionStore.swift  StoredSession.swift  KeychainStore.swift  ServerAddress.swift
  Media/      MediaLoader.swift  RemoteImage.swift  FileStore.swift  PlayerFactory.swift
  Features/   Connect/  SignIn/  Chats/  Topics/  Chat/  Chat/Cells/  Media/  Search/  Settings/
  Shared/     ErrorBanner.swift  RelativeDate.swift
  Resources/  Assets.xcassets  PrivacyInfo.xcprivacy  en.lproj/  es.lproj/
TGArchiveTests/   MockURLProtocol.swift  Fixtures/*.json  *Tests.swift
TGArchiveUITests/ *.swift
scripts/          pick-simulator.sh  demo-server.sh  capture-fixtures.sh  check-required-reason-apis.sh  mini-test.sh
```

**`ServerAddress`** (`Session/ServerAddress.swift`): a value type with `baseURL: URL` and pure parsing. `ServerAddress.parse(_ text: String) -> Parsed?` accepts `host`, `host:8000`, `http(s)://host[:port][/prefix]` and a full share link `https://host[/prefix]/#token=VALUE`, returning the address and the token split apart. The scheme defaults to `https`. A path prefix is kept and every request is built under it, because the app builds every URL itself (it never uses the root-absolute `avatar_url` or `media.url` strings from the server). The token is passed through untouched: the server only requires a non-empty string, and the demo archive's share token is not hex. Unit tested, including the non-hex token.

**`Endpoint`** (`API/Endpoint.swift`): an enum with one case per route in section 2, plus `health`. `func request(base: URL) -> URLRequest`. `MessageCursor` is `.newest`, `.before(date: Date, id: Int)`, `.beforeID(Int)` or `.after(id: Int)`. Media URLs come from `Endpoint.media(ref:key:)`, `.thumbnail(size:ref:key:)`, `.avatar(ref:)`, `.senderAvatar(ref:messageID:)`.

**`APIClient`** (`API/APIClient.swift`): `final class APIClient: Sendable`, one per signed-in session, built from a `ServerAddress` and an optional cookie value. It owns one `URLSession` made from `URLSessionConfiguration.default` with `httpCookieStorage = nil`, `httpShouldSetCookies = false`, `timeoutIntervalForRequest = 30`, and a dedicated `URLCache` (20 MB memory, 300 MB disk, directory `Caches/TGArchiveHTTP`). It adds `Cookie: viewer_auth=<value>` itself on every request. Methods: `get<T: Decodable & Sendable>(_ endpoint: Endpoint) async throws(APIError) -> T`, `post<T>(_ endpoint: Endpoint, body: some Encodable) async throws(APIError) -> (value: T, setCookie: HTTPCookie?)`, and `data(for endpoint: Endpoint) async throws(APIError) -> Data` for media bytes. JSON routes use `.reloadIgnoringLocalCacheData`; media routes use `.useProtocolCachePolicy` so the cache revalidates with `If-None-Match` and a `304` reuses the stored bytes. The login and token calls read `Set-Cookie` through `HTTPCookie.cookies(withResponseHeaderFields:for:)`. The `X-Viewer-Only` header is never sent: it would make the master login fail, and the app simply never calls a master route.

**`APIError`** (`API/APIError.swift`): `enum APIError: Error, Equatable { case unauthorized, forbidden(detail: String?), notFound, rateLimited, badRequest(detail: String?), serverUnavailable(detail: String?), server(status: Int, detail: String?), notAnArchiveServer, transport(URLError.Code), decoding(String) }`, mapped from the status code and the `{"detail": "..."}` body, with one localized message per case.

**Models** (`API/Models/`): `Decodable`, `Sendable`, `Hashable` structs that mirror the API doc, decoded by **`ArchiveDecoder`**: `keyDecodingStrategy .convertFromSnakeCase`, a date strategy that accepts ISO 8601 with or without fractional seconds and with or without an offset and reads a missing offset as UTC, and a `FlexBool` wrapper that decodes `0`/`1`/`true`/`false`/`null`, because the archive sends `is_outgoing`, `is_deleted`, `is_pinned`, `is_forum`, `is_archived`, `is_closed` as integers on some routes and booleans on others. Every field except `id` and `date` is optional. An unknown `media.type` decodes to `.unsupported` and renders as a neutral row; a page never fails because of one message. The types:

- `AuthCheck { authenticated, authRequired, role?, username?, noDownload?, setupRequired?, proxyAuth? }`
- `LoginResponse { success, role?, username?, noDownload?, message? }`
- `ChatsPage { chats: [Chat], total, hasMore }`, `Chat { ref, type, title?, firstName?, lastName?, username?, isForum: FlexBool, isArchived: FlexBool, accounts: [Int]?, avatarURL?, preview: ChatPreview? }`, `ChatPreview { messageID, date, text?, sender?, kind, outgoing, action?, actionTitle? }`
- `Folder { id, title, emoticon?, chatCount }`, `Topic { id, title, iconEmoji?, iconColor?, isClosed, isPinned, isHidden, messageCount?, lastMessageDate? }`
- `Message { id, date, text?, senderID?, senderName?, firstName?, lastName?, isOutgoing, isDeleted, isPinned, deletedAt?, editDate?, editHide: Int?, versionCount?, replyToMsgID?, replyToTopID?, replyToText?, replyToSenderName?, replyToMediaType?, media: MessageMedia?, reactions: [Reaction]?, removedReactions: [RemovedReaction]?, snapshots: Snapshots?, rawData: RawData?, senderAvatarURL? }`
- `MessageMedia { id (the media key, `{message_id}_{type}`), type: MediaType, url?, fileName?, fileSize?, mimeType?, width?, height?, duration?, downloaded, skipReason?, noDownload?, transcripts: [Transcript]? }`, `MediaType` with the archive's kinds plus `.unsupported`
- `RawData { entities: [Entity]?, forwardFromName?, groupedID: String? (decodes a number or a string), geo?, venue?, geoLive?, contact?, poll: Poll?, serviceType?, actionType?, newTitle?, sticker: { emoji? }? }`, `Snapshots { poll: Snapshot<Poll>? }`
- `Reaction { emoji, count }`, `RemovedReaction { emoji, count, countBefore?, removedAt?, backAt? }`, `Transcript { status, text?, language? }`
- `SearchPage { hasMore, indexed, results: [SearchResult] }`, `SearchResult { id, date, text?, senderName?, isDeleted, topicTitle?, matchedIn?, chat: SearchChat }`, `SearchChat { ref, title?, firstName?, lastName?, username?, type, isForum, avatarURL? }`
- `ArchiveStats { chats?, messages?, mediaFiles?, lastBackupTime?, showStats? }`

**`StoredSession`** (`Session/StoredSession.swift`): `Codable` value `{ server: ServerAddress, cookie: String?, cookieExpires: Date?, username: String?, role: Role, noDownload: Bool }`, `Role` is `master`, `viewer`, `token`, `anonymous`. **`KeychainStore`**: `kSecClassGenericPassword`, service `<bundle id>.session`, account `current`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synchronizable, holding one JSON-encoded `StoredSession`: `load()`, `save(_:)`, `delete()`.

**`SessionStore`** (`Session/SessionStore.swift`): `@MainActor @Observable final class`. State: `phase` (`.restoring`, `.connect`, `.signIn(ServerAddress, prefilledToken: String?, reason: EndReason?)`, `.ready(Session)`), where `Session` holds the `StoredSession`, the `APIClient` and the `MediaLoader`. Mutators: `connect(_ text: String)`, `signIn(username:password:)`, `signIn(token:)`, `continueAnonymously()`, `restore()`, `signOut()`, `sessionEnded()`. Nothing else changes session state. `TGArchiveApp` injects it with `.environment(sessionStore)`. Stage 4 note: `RootView` owns the store as `@State` and injects it, so `TGArchiveApp` stays a one-line scene. Stage 3 note: `Session` holds the `StoredSession` and the `APIClient` only, because `MediaLoader` is stage 5's file; stage 5 builds its loader from `client.urlSession` and joins the wipe through `SessionStore.addWipeStep(_:)`, and passes the failing client to `sessionEnded(_:)` so a late 401 from an older session is ignored.

**`MediaLoader`** (`Media/MediaLoader.swift`): `actor`, one per session, sharing the client's `URLSession`. `NSCache<NSString, UIImage>` (countLimit 300) keyed by request URL, an in-flight `[URL: Task<UIImage, Error>]` that collapses duplicate requests while scrolling, decoding with `CGImageSourceCreateThumbnailAtIndex` sized to the screen off the main actor, `purge()`. A `401` from any image load reaches `SessionStore.sessionEnded()`. **`RemoteImage`** is the SwiftUI view that replaces `AsyncImage`, which cannot send the cookie: `RemoteImage(endpoint:) { image in } placeholder: { }`, loading in `.task(id:)` so a scrolled-away cell cancels its download. **`FileStore`** downloads a document to `tmp/Media/<ref>/<key>/<file_name>` for Quick Look and has `wipe()`. **`PlayerFactory`** builds an `AVPlayer` from an `AVURLAsset` that carries the session cookie through the public `AVURLAssetHTTPCookiesKey` (an `HTTPCookie` built from the stored value, domain = server host, path `/`, `secure` only when the base URL is https); the private header-fields key is never used.
Stage 5 note: an image cache keyed by URL alone would show a copy without asking the server, which section 3.4 forbids, so every load goes through the `URLCache` (a `304` when nothing changed) and the decoded image is kept under URL, pixel size and `ETag`, which only spares the decode. `RemoteImage`'s placeholder also takes the `MediaFailure` (nil while loading) to show the downloads-off and missing tiles. Views reach the session's loader through `MediaLoader.current(for:in:)`, which joins the sign-out wipe once.

**Feature models**: one `@MainActor @Observable final class` per list screen, owned by its view with `@State` and built from the environment's session: `ChatListModel`, `ChatThreadModel`, `SearchModel`. Each holds its items, cursor, `isLoading`, `error`, and one load `Task` that is never re-entered and is cancelled on disappear. `MessageWindow` (`Features/Chat/MessageWindow.swift`) is a pure value type with the thread's ordered array, `hasOlder`, `hasNewer`, and merge-without-duplicates by id; it is unit tested without the network.

### 3.3 Where state lives

Three places. The Keychain holds the session. `SessionStore` on the main actor holds the phase and the live `Session`. Each screen's model holds its pages. The `URLCache`, the image cache and `tmp/Media` are derived and are wiped together. `UserDefaults` holds only the last server address, the last username, and an install marker (reason `CA92.1`).

### 3.4 Networking, cookies and the cache

- One `URLSession` per session, no shared cookie storage, the cookie sent as an explicit header. A `Secure` cookie therefore still works against a plain-http server on the local network, and `HTTPCookieStorage.shared` never holds it.
- ATS allows plain http only to local addresses (IP literals, `.local`, unqualified names, loopback) through `NSAllowsLocalNetworking`. Any other host needs https; ConnectView says so when an http address outside the local network fails: "Remote servers need https. Put your server behind a reverse proxy with a certificate." Stage 3 verifies on the simulator which of a private IPv4, `.local` and loopback get through and records the result in this section.
- Measured by stage 3 on the iOS 27 simulator (`LiveServerTests`, `NSAllowsLocalNetworking` only): plain http reaches loopback (`127.0.0.1`, `localhost`), `.local` names, unqualified names and private IPv4 literals (`10.x`, `192.168.x`); a public hostname and a public IPv4 literal fail at once with `URLError.appTransportSecurityRequiresSecureConnection` (-1022), which `APIError` words as the https sentence above.
- Media, thumbnails and avatars are stored by `URLCache` and revalidated on every reuse because the server sends `private, no-cache` with an `ETag`: a `304` reuses the bytes without a body, a `401`/`403`/`404` is handled as below. That is the same check the server runs for browsers. JSON is never served from the cache.
- `POST /api/logout` carries the cookie and a 5 s timeout; its result is ignored (section 4).

### 3.5 Error mapping

| Status or event | Where | Meaning and what the app does |
|---|---|---|
| 401 | `/api/login`, `/auth/token` | Wrong credentials. "Wrong username or password" or "This link is invalid, revoked or expired". The session is untouched. |
| 401 | Any other route, including media and thumbnails | The session ended on the server: expiry, eviction by an 11th login, logout elsewhere, an admin edit of the viewer or token, or end-all. `APIClient` throws `.unauthorized`; the model or `MediaLoader` calls `SessionStore.sessionEnded()` (section 4). |
| 403 | Media bytes, thumbnails | Downloads are off for this login. The cell shows the "Downloads are off for this login" tile. The session stays. The app knows this up front from `no_download` and from `media.url == nil`, so it normally never sends the request. |
| 403 | Anything else | Cannot happen: the app calls no master route and sends no `X-Viewer-Only`. Shown as a generic error. |
| 404 | A chat route | The chat is unknown or no longer visible to this login. ChatView pops with "This chat is no longer available to this login" and the list refreshes. |
| 404 | A thumbnail | No thumbnail for this file (videos without server-side ffmpeg, animated stickers). The cell shows its placeholder. |
| 429 | `/api/login`, `/auth/token` | Rate limit. "Too many sign-in attempts from your network. Wait about 5 minutes." The button is disabled for 60 s. Never retried automatically. |
| 503 | Any route | "Your server can't reach its database" or "Your server has no login mode configured" (`setup_required`). Banner with retry; the session stays. `POST /auth/token` answers 500 `Database not available` for the same condition and maps the same way. |
| Transport error | Any route | Banner with retry. On launch it never signs the user out. |
| Decoding failure | Any route | `.decoding`, logged with `os.Logger` at `.debug` without message text or names. On ConnectView a failed `AuthCheck` decode means `.notAnArchiveServer`. |
| WebSocket close 4001 | `/ws/updates` | v1 opens no socket. When live updates arrive, a 4001 close (`Session revoked`) calls the same `sessionEnded()`; 4003 (origin) and 1013 (too many sockets) are shown, never treated as a sign-out. |

### 3.6 Rendering the thread

- Layout: `ScrollView { LazyVStack { ForEach(window.messages) }.scrollTargetLayout() }` with `.defaultScrollAnchor(.bottom)` and `.scrollPosition(id:)`. The window is kept oldest-first; each newest-first page is reversed and merged. Before older messages are prepended the position is pinned to the current top id so nothing jumps. A sentinel at the top loads the next older page. Opening at an anchor (a search hit) loads `before_id = anchor + 1` for the anchor and older, then pages newer with `after_id = newest loaded id` until a page comes back short; a "Jump to latest" button appears in that mode.
- Stage 6 note: `.defaultScrollAnchor(.bottom)` for every role made the lazy stack re-lay itself out without end near the top of a thread with rows of mixed heights, so the bottom anchor is set for `.initialOffset` only; the first page is then scrolled to its newest message once it arrives, and an older page is pinned to the message that was on top.
- Day headers between local days. Outgoing messages (`is_outgoing`) on the right in the accent colour, incoming on the left; in groups and channels the sender name sits above incoming bubbles, with the sender's avatar from `sender_avatar_url`. `.textSelection(.enabled)` on text.
- Text formatting from `raw_data.entities` into an `AttributedString`: bold, italic, underline, strikethrough, code, pre, url, text_url, mention, hashtag. A custom emoji entity renders the characters already in the text, which Telegram sets to the ordinary emoji.
- Reply quote from `reply_to_sender_name` and `reply_to_text` (or a label for `reply_to_media_type`); tapping does nothing in v1. Forward line from `raw_data.forward_from_name`.
- Service rows: a centred grey capsule. The text is `text` when the archive stored a sentence; otherwise it is worded from `raw_data.action_type` with the server's own table: `chat_joined_by_link` "joined the group via invite link", `chat_joined_by_request` "joined the group", `chat_edit_photo` "changed the group photo", `chat_delete_photo` "removed the group photo", `chat_edit_title` "changed the group name to \"<new_title>\"", `chat_create` "created the group \"<new_title>\"", `channel_create` "created the channel \"<new_title>\"", each prefixed with the sender name; `chat_add_user` "Someone was added to the group" and `chat_delete_user` "Someone was removed from the group" (the affected user is not stored). An unmapped action shows nothing but the capsule's glyph. The chat list preview uses the same table through `preview.action` and `preview.action_title`.
- Marks: "edited" when `(edit_date != nil && edit_hide != 1) || version_count > 0`, the server's own pencil rule. A message with `is_deleted` renders muted with a trash glyph and "Deleted in Telegram". `is_pinned` gets a pin glyph.
- Reactions: one chip per live emoji with its count. A `custom_<id>` reaction shows a sparkle glyph with the count. `removed_reactions` fold into one muted chip, "N taken back", not tappable.
- Media cells, each a native view in `Features/Chat/Cells/`:
  - `PhotoCell`: the 400 px thumbnail at the aspect ratio from `width`/`height` so rows do not jump; tap opens MediaViewer. Album members (same `grouped_id`) render as consecutive photo bubbles in v1.
  - `VideoCell` (video, animation): tries the 400 px thumbnail (the server makes one when it has ffmpeg), falls back to a dark tile; play glyph and duration; tap opens MediaViewer.
  - `VideoNoteCell`: a circle; tap opens MediaViewer.
  - `VoiceCell` and `AudioCell`: play/pause, duration, a progress bar, and under it the newest `done` transcript as collapsible text. Playback goes through `PlayerFactory`. Voice notes are Ogg/Opus files, which AVFoundation on iOS does not play; stage 8 confirms this against the demo server and, when confirmed, the cell shows the duration and transcript and "Voice note playback isn't supported in this version" when tapped. Audio files AVFoundation plays (m4a, mp3, mp4) play.
  - Stage 7 note: measured on the iOS 26.5 simulator, AVFoundation reads and decodes Ogg/Opus: `PlayerFactoryTests` decodes an Ogg/Opus fixture to PCM and opens the demo server's voice notes over http with the session cookie. Voice notes therefore play in the cell like any audio file. When AVFoundation on a device cannot read a file, the cell says "This voice note can't be played on this device" and the transcript stays under it.
  - `DocumentCell`: file icon, `file_name`, `file_size`; tap downloads through `FileStore` and opens Quick Look.
  - `StickerCell`: a static WebP (`image/webp`) renders as an image at 160 pt; `.tgs` and `.webm` stickers show `raw_data.sticker.emoji` at 64 pt, or a generic sticker glyph.
  - `LocationCell` (geo, venue, geo_live): a non-interactive MapKit `Map` with a `Marker` at `lat`/`long`, the venue title and address under it, tap opens Apple Maps. A location without a point shows "Location".
  - `ContactCell`: name and phone from `raw_data.contact`.
  - `PollCell`: question, answers with percentage bars from `results`, "Closed". `snapshots.poll.payload` (the newest state) overrides `raw_data.poll` field by field.
  - `MediaPlaceholder`: "Downloads are off for this login" (`no_download` or `media.url == nil` with downloads off), "Not downloaded (too large)" (`skip_reason` oversize), "Not downloaded (filtered)" (filtered), "Not downloaded yet" (`downloaded` false), "Unsupported message" (`.unsupported`). No request is sent for any of these.
- Thumbnails: the client builds `/media/thumb/400/{ref}/{media.id}` itself; `media.id` is the media key (`1274_photo`). The server's `thumb_url` field is ignored.

### 3.7 Concurrency and errors

Swift 6 strict. Views own `@MainActor @Observable` models; `APIClient` is an immutable `Sendable` class; `MediaLoader` is an actor; everything crossing an actor boundary is a `Sendable` value. Every load runs inside `.task` or `.task(id:)`, so leaving a screen cancels it. No detached tasks, no Combine, no `@unchecked Sendable`. One `ErrorBanner` view modifier per screen shows `APIError`'s localized message with Retry; only `.unauthorized` escalates to `SessionStore`.

## 4. Session handling

The rule: one install holds at most one server session, the app never creates one the user did not ask for, and every exit path runs the same local wipe.

1. **Connect.** `GET /api/auth/check` on the typed or pasted address. A body that does not decode to `AuthCheck` means "This does not look like a Telegram-Archive server". `setup_required` shows "Your server has no login mode configured" with a docs link. `proxy_auth` shows "Proxy sign-in isn't supported in this version". `auth_required == false` is anonymous mode: a `StoredSession` with no cookie and role `anonymous` is saved and the app goes to `.ready`. Otherwise SignInView, with the token prefilled when a share link was pasted.
2. **Sign in.** If a `StoredSession` already exists (switching server, user or link), the app first runs `signOut()` (step 4), so a sign-in never strands a server session. Then `POST /api/login {username, password}` or `POST /auth/token {token}`. On 200 the `viewer_auth` cookie's value and `expiresDate` are read from `Set-Cookie`; the password and token are never written anywhere, so the app cannot log in again on its own. `GET /api/auth/check` with the cookie confirms `authenticated == true` and gives `role`, `username` and `no_download`; the `StoredSession` is saved to the Keychain and the phase becomes `.ready`. A 200 from `/api/login` with `message` and no cookie is anonymous mode and is handled as in step 1. Only one sign-in request is ever in flight, and none is retried automatically, because both routes share the 15-per-5-minutes limit per client IP (behind a proxy without `TRUST_PROXY_HEADERS` every client shares one IP).
3. **Launch.** `restore()` loads the Keychain item. None: `.connect`, prefilled from UserDefaults. `cookieExpires` in the past: delete it and show `.signIn` with reason `.expired`, with no network call. Otherwise the phase becomes `.ready` at once and `GET /api/auth/check` runs in the background: `authenticated == false` runs `sessionEnded()`; a transport error shows an offline banner and keeps the session. The app never logs in on its own, so a launch never spends a session slot.
4. **Sign out** (Settings). `POST /api/logout` with the cookie, 5 s timeout, result ignored (offline is fine; the server session then lasts until it expires, and Settings says so once). Stage 4 note: Settings is gone once the wipe runs, so the sign-in screen that follows shows that note. Then the local wipe, the native equivalent of the server's `Clear-Site-Data: "cache"`: delete the Keychain item, `URLCache.removeAllCachedResponses()`, `MediaLoader.purge()`, `FileStore.wipe()`, stop any player, reset every feature model, phase `.signIn` with the same server prefilled. In anonymous mode the button reads "Disconnect", makes no server call, and goes to `.connect` (an anonymous server has no sign-in to return to).
5. **Session ended on the server.** A 401 from any non-login route, or `authenticated == false` from the launch check. The server does not say which cause it was. `sessionEnded()` runs the same wipe as step 4 without the logout call and shows `.signIn` with the banner "Your session on this server ended. It may have expired, been signed out elsewhere, or the link may have been revoked. Sign in again." It is idempotent: a flag on the main actor collapses a burst of 401s from parallel thumbnail loads into one transition. Requests in flight are cancelled through the root task.
6. **The 10-session cap.** One slot per install, taken only by a deliberate sign-in and released by sign-out or by the sign-in-replaces-sign-in rule. Reinstall: the Keychain survives app deletion, so on a launch with no install marker in UserDefaults the app sends a best-effort `POST /api/logout` with any leftover cookie, deletes it and writes the marker. SignInView's footer says in one line that the app keeps one session and signs out cleanly, so it never pushes a browser session out.
7. **403, 404, 429, 503** keep the session (section 3.5).

## 5. The demo server

`scripts/demo-server.sh` runs a synthetic Telegram-Archive on any Mac with Xcode (a developer machine or a CI runner), so the UI tests and the store screenshots never touch a real archive. It takes `start`, `stop`, `status` and `reset`; `DATA_DIR` (default `./demo-data`) holds the archive, the pid and the log, `SRC_DIR` (default `./demo-src`) the server checkout, and `PORT` and the master login come from the environment with the demo defaults:

1. Shallow-clone `GeiserX/Telegram-Archive` at the pinned tag (`v9.3.1` to start; bump deliberately) into `src/`.
2. `uv sync --locked` in `src/` (uv fetches the Python it needs; `ffmpeg` on PATH is optional and only adds the voice notes, the round video and the video sticker).
3. `python -I src/scripts/generate_dummy_db.py --data-dir ./demo-data --force` ([the generator](https://github.com/GeiserX/Telegram-Archive/blob/main/scripts/generate_dummy_db.py)). Every person, chat and message in it is invented. The script seeds two viewer accounts (`family`, active, three chats; `work-readonly`, inactive, downloads off), both with `DEMO_VIEWER_PASSWORD`, and one live share link with `DEMO_SHARE_TOKEN` (downloads off, one chat, expires 14 days after generation; `reset` regenerates it). The constants are public in that script by design.
4. Start `uvicorn telegram_archive.web.main:app` on `127.0.0.1:${PORT:-8000}` with `BACKUP_PATH`, `DB_TYPE=sqlite`, `DB_PATH`, `VIEWER_TIMEZONE=UTC`, and a master login whose password is a documented demo constant, detached from the shell (`perl -MPOSIX=setsid` on macOS), pid and log files beside the data.
5. Wait for `GET /api/health` to answer 200, then print the base URL, the master, viewer and share-link credentials.

What it serves, as checked against the live script: 15 chat rows for the master (private chats, groups, a forum with three topics, channels, one archived chat, a supergroup two accounts hold listed once), two folders, 409 messages covering photos, an album, static and animated stickers, voice notes with transcripts, a round video, videos, documents (one filtered, one oversize), a location, a venue, a live location, a contact, a poll with a later snapshot, replies, forwards, reactions with taken-back ones and custom ones, edits, kept deletions, pinned messages and service rows. `/api/chats/{ref}/messages` is a bare JSON array; `/api/chats` is an object. Thumbnails exist for images and static stickers; videos and `.tgs` stickers answer 404. A messages page is ordered by date, not by id: in the demo some older-dated messages have higher ids, so ids are not a time order and a merge must sort by date, then id.

`scripts/capture-fixtures.sh` logs in to a running demo and writes the JSON fixtures under `TGArchiveTests/Fixtures/` (auth check signed out, signed in, by share link and after logout; login, token login and logout; the chat list in both archived states, one chat, folders, the archived count, topics and one topic's page, every chat's first page plus a cursor page where there is one, the anchored pages before and after a search hit, pinned, two message version lists, search, chat stats, custom emoji, stats, the share link's chats and messages with downloads off, and the 401, 403 and 404 error bodies). There is no 429 fixture: getting one costs the 15 attempts the rate limit allows, so its body (`{"detail": ...}`, the same shape as every error) is left to a hand-written test. The fixtures hold invented data only, so they are committed. The capture logs in three times per run (master, one wrong password, the share link), under the rate limit, and fails unless the saved messages hold every kind of message the generator makes.

CI starts the demo on the `macos-latest` runner (`brew install uv`), runs the unit tests against the fixtures and the UI tests against `http://127.0.0.1:8000` (loopback, allowed by `NSAllowsLocalNetworking`), and stops it. The public demo for App Review is the same script on a host with a public hostname and https; its address is never written in this repo.

## 6. App Review plan

**What the reviewer gets** (all in App Review Notes, never in the repo): the public demo server's https URL, the `family` viewer login, the share link built as `https://<demo>/#token=<DEMO_SHARE_TOKEN>` (so the reviewer also sees the share-link path and the downloads-off state), and the physical-device screen recording of connect, sign in, browse a thread, open a photo, search, open a hit, sign out. The demo archive is regenerated before each submission so the share link has not expired, the host has a hostname (never an IP literal; Apple reviews from an IPv6-only network), and `TRUST_PROXY_HEADERS=true` is set behind the proxy so the reviewer's attempts do not share the rate-limit bucket with everyone else. "Sign-in required" is ticked.

**Notes text outline** (the six-item Guideline 2.1 answers, pre-filled before the first submission):

1. Recording attached.
2. Purpose: people who back up their own Telegram history with the open source Telegram-Archive server read that backup on their phone. The app is read-only and shows only the signed-in user's own archive.
3. Setup: install the server (link to its docs), enter its address in the app, sign in with a viewer account or paste a share link. Demo URL, login and link follow.
4. External services: only the server the user enters and controls. The app never contacts Telegram; the server uses the Telegram API to make the backup. No analytics, ads, purchases or tracking. Accounts are created and deleted by the server's owner on the server, so in-app account deletion (5.1.1(v)) does not apply, and there is no third-party social login, so Sign in with Apple (4.8) does not apply.
5. No regional differences.
6. Not applicable: no regulated content, and the app shows only the user's own private backup; there is no posting, no feed, no discovery and no contact between app users (1.2 does not apply).

**Why 4.2 is met**: no `WKWebView` anywhere; native lists, bubbles, Dynamic Type and VoiceOver labels, AVKit playback, Quick Look documents, MapKit locations, native search with anchored navigation, Keychain session, share sheet, dark mode. The Notes name these.

**Privacy**: label "Data Not Collected" (nothing leaves the device except requests to the user's own server). `PRIVACY.md` in the repo is the privacy policy URL. Manifest as in section 3.1. `ITSAppUsesNonExemptEncryption` false (system TLS only).

**Trademarks (5.2.1, 4.1)**: the rules in section 1. The subtitle is "Read your self-hosted chat backup". Keywords leave out "telegram".

**Screenshots (2.3.3)**: captured by a UI test from the synthetic archive only: chat list, a thread with a photo and a poll, a location card, search results, the media viewer. Never a real archive.

**Age rating**: the questionnaire answered as none for every listed content category, no unrestricted web access, no user-to-user communication in the app; the result is 4+.

**GPL ([NOTICE](../NOTICE))**: the About screen links the public repo, and the store description names it, so every store recipient can get the Corresponding Source.

## 7. Cut from v1, one reason each

- Live updates over `/ws/updates`: the archive is read after the fact, pull to refresh covers it; 4001 handling is reserved (section 3.5).
- Web Push and `/api/push/*`: browser push only, and APNs would need server work.
- Requesting transcripts (`POST .../transcripts`): a write with its own rate limit; transcripts already in the payload are shown.
- Message edit history (`/versions`): the "edited" mark is enough to know; the sheet is v1.1.
- Reaction history and poll or preview snapshot history: only the newest state is shown.
- Pinned messages list, jump to date and the calendar, chat stats, media gallery, avatar history, `deleted_only` and `edited_only` filters, in-chat search: each is one more screen on the same routes; global search covers finding things in v1.
- Album grid by `grouped_id`: photos render as consecutive bubbles; the grid is layout work with no new data.
- Link preview cards (`raw_data.webpage`): URLs render as tappable links.
- Custom emoji images (`/api/custom-emoji`, `/media/emoji`): the ordinary emoji is already in the text; reactions show a glyph.
- Animated `.tgs` (needs Lottie) and `.webm` stickers (AVFoundation does not decode WebM): the alt emoji is shown.
- Rich Text Editor block trees and spoiler animation: plain text with basic entities.
- Hashtag and cashtag pages, the change feed, export, every master and admin route, `/api/status`, `/media/open*`.
- Proxy-identity servers (`AUTH_PROXY_HEADER`): they need an embedded web login; detected and explained.
- Several servers or accounts at once, the account switcher.
- iPad layouts, widgets, Shortcuts, Spotlight (it would copy private text into the system index), an offline mirror.
- Universal links or a URL scheme for share links: the link's domain is the user's own, so universal links cannot work; `PasteButton` covers it. No QR scanner: the server shows no QR anywhere.
- A built-in "Try the demo" button: it would put a hostname in the public repo and the binary.
- Voice note (Ogg/Opus) playback: AVFoundation does not play the Ogg container, and a decoder would break the no-packages rule; the transcript and duration are shown. Reconsidered when the server offers another rendition.
- Stage 7 note: voice note playback is in v1 after all, because AVFoundation does play Ogg/Opus (section 3.6).

## 8. Implementation stages and file ownership

Stages in the same group run in parallel and never touch the same file. A later stage may edit a finished earlier stage's files where this list says so. Every build, test, simulator run and demo server runs on a Mac with Xcode, never on the editing laptop. Each stage ends with a PR, CI green, and a one-line note in this doc only when a fact here turned out wrong.

**Group A**

- **Stage 1, scaffold and CI.** Owns `project.yml`, `.gitignore`, `.github/workflows/ci.yml`, `scripts/pick-simulator.sh`, `scripts/check-required-reason-apis.sh`, `TGArchive/App/TGArchiveApp.swift`, `TGArchive/App/RootView.swift` (placeholder), `TGArchive/Resources/**`, `TGArchiveTests/SmokeTests.swift`, `TGArchiveUITests/LaunchTests.swift`. Done when CI runs unit and UI tests on `macos-latest`, a Release build with `CODE_SIGNING_ALLOWED=NO`, a test-count gate read from the xcresult that was proven red once, and the Required Reason API grep with a positive control.
- **Stage 2, demo server and fixtures.** Owns `scripts/demo-server.sh`, `scripts/capture-fixtures.sh`, `scripts/mini-test.sh` (builds and tests a checkout on a Mac with Xcode over ssh, with the CI test-count gate; every later stage uses it), `TGArchiveTests/Fixtures/*.json`. Done when the script starts, resets and stops the demo and the fixtures are captured from it.

**Stage 3, API, models and session** (after A). Owns `TGArchive/API/**`, `TGArchive/Session/**`, `TGArchiveTests/MockURLProtocol.swift`, `TGArchiveTests/DecodingTests.swift`, `TGArchiveTests/ServerAddressTests.swift`, `TGArchiveTests/SessionStoreTests.swift`, `TGArchiveTests/KeychainStoreTests.swift`. Tests: every fixture decodes; `FlexBool` and the date rule; status-to-`APIError` mapping; `Set-Cookie` captured and the `Cookie` header sent; sign-in while signed in calls `/api/logout` first; a 401 burst gives one transition; 429 never retries; an expired stored session makes no network call; sign-out wipes even offline; a non-hex token is accepted; the reinstall cleanup. Records the ATS result in section 3.4.

**Group B** (after 3)

- **Stage 4, onboarding, settings and the tab shell.** Owns `TGArchive/App/MainTabView.swift`, edits `RootView.swift`, `TGArchive/Features/Connect/**`, `TGArchive/Features/SignIn/**`, `TGArchive/Features/Settings/**`, `TGArchive/Shared/ErrorBanner.swift`, `PRIVACY.md`. Chats and Search tabs hold placeholders it does not own.
- **Stage 5, media loading, chat list and topics.** Owns `TGArchive/Media/MediaLoader.swift`, `RemoteImage.swift`, `FileStore.swift`, `TGArchive/Shared/RelativeDate.swift`, `TGArchive/Features/Chats/**` (`ChatListView`, `ChatListModel`, `ChatRow`, `AvatarView`, `PreviewText`, `Route.swift`), `TGArchive/Features/Topics/**`, `TGArchiveTests/ChatListModelTests.swift`, `TGArchiveTests/PreviewTextTests.swift`. Its `navigationDestination(for: Route.self)` pushes a placeholder for `.chat`.

**Stage 6, chat thread** (after B). Owns `TGArchive/Features/Chat/**` including `Cells/`, `TGArchiveTests/MessageWindowTests.swift`, `TGArchiveTests/EntityTextTests.swift`, `TGArchiveTests/ServiceTextTests.swift`; edits `ChatListView.swift` to push `ChatView`, and `MainTabView.swift` to replace the Chats placeholder.

**Group C** (after 6)

- **Stage 7, media viewer.** Owns `TGArchive/Features/Media/**`, `TGArchive/Media/PlayerFactory.swift`, `TGArchiveTests/PlayerFactoryTests.swift`; edits the cells in `Features/Chat/Cells/` to present the viewer. Confirms the Ogg/Opus result on the simulator and records it in section 3.6.
- **Stage 8, search.** Owns `TGArchive/Features/Search/**`, `TGArchiveTests/SearchModelTests.swift`; edits `MainTabView.swift` to replace the Search placeholder. Debounce 300 ms, 1 to 500 characters, offset capped at 5000, `indexed == false` banner, anchored open through `Route.chat(ref:anchor:)`.

**Group D** (after C)

- **Stage 9, UI tests and screenshots.** Owns `TGArchiveUITests/**` (except `LaunchTests.swift`, which it may edit), `.github/workflows/ci.yml` (edits to start the demo). Against the live demo: sign in as the viewer, open every chat and scroll to the top, open a photo, search and open a hit, sign in with the share link and see the downloads-off tiles, sign out; a deliberately wrong password proves the 401 path can fail the test. A screenshot test writes the store screenshots.
- **Stage 10, release path and store material.** Owns `.github/workflows/release.yml`, `TGArchive/Resources/Assets.xcassets/AppIcon.appiconset/**` (the final icon), `docs/app-store/description.en.md`, `docs/app-store/description.es.md`, `docs/app-store/review-notes-template.md` (placeholders only), `README.md`.
