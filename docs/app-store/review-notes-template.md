# App Review notes

Paste everything under "Notes" into App Review Information > Notes in App Store Connect (4000 characters at most). Leave "Sign-in required" unticked: the reviewer uses the demo built into the app, so there is no review login and no demo server to keep alive.

## Notes

No account or sign-in is needed for review. Tap "Try the Demo" on the first screen.

1. What to look at. The demo starts at app launch: on the first screen tap "Try the Demo" (below "Have a share link?"). It opens an invented archive built into the app, labelled "Demo" at the top of every screen. From there: browse the chat list, open "Weekend Hikers" to read a thread with photos, a poll and a voice-note transcript, tap a photo to open it full screen, open the Search tab and search for "trail", tap a result to jump to it in its chat, then tap "Exit Demo" (top of the screen, or Settings) to return to the first screen.

2. Purpose and audience. TG Archive is the reader for Telegram-Archive (https://github.com/GeiserX/Telegram-Archive), an open-source backup server that people run themselves to keep a backup of their own chat history. The app lets them read that backup on their iPhone. It is a read-only viewer: it shows only the user's own exported archive from the server they run. It is not a Telegram client. It does not use the Telegram API, cannot send or receive messages, and has no contact with Telegram.

3. Setup and access. A real user installs the server, enters its address in the app, and signs in with an account their own server issues, or pastes a share link from that server. We run no server and hold no accounts: every account lives on the user's own server. The demo needs none of this.

4. External services and endpoints. In demo mode there is no archive server: the invented archive and its photos ship inside the app. Location cards use Apple Maps (MapKit), which loads map tiles from Apple; the demo's videos and voice notes are not bundled, so they show as unavailable. Outside the demo, the app contacts the server address the user types, over https, to read their chats, messages, media and search results, plus Apple Maps for location cards. Plain http is allowed only for addresses on the user's local network (NSAllowsLocalNetworking), because many people run the server at home on a LAN address without a certificate; arbitrary loads are not allowed. No analytics, ads, purchases, tracking or third-party SDKs. Accounts are created and deleted by the server's owner on the server, so in-app account deletion (5.1.1(v)) does not apply, and there is no third-party social login, so Sign in with Apple (4.8) does not apply.

5. Regional differences. None. The app works the same in every region.

6. Regulated or third-party content. Not applicable: the app shows only the user's own private backup from their own server. There is no posting, no feed, no discovery and no contact between app users, so 1.2 does not apply.

Native functionality (4.2): there is no web view. Chats, threads and search are native SwiftUI lists with Dynamic Type, dark mode and VoiceOver labels; photos open in a zoomable viewer, video and audio play through AVKit, documents open in Quick Look, locations show in MapKit, the session lives in the Keychain, and files go through the share sheet.

Source code: https://github.com/GeiserX/TG-Archive-iOS

TG Archive is part of the open-source Telegram-Archive project and is independent of Telegram; the server you run uses the Telegram API.
