# App Review notes template

Fill the placeholders and paste everything under "Notes" into App Review Information > Notes in App Store Connect (4000 characters at most). The placeholders stay placeholders in this file: the demo address, the login and the share link are written only in App Store Connect, never in this repository.

| Placeholder | What goes there |
|---|---|
| `<DEMO_URL>` | The public demo server's https address. A hostname, never an IP literal: App Review tests from an IPv6-only network. |
| `<VIEWER_USERNAME>`, `<VIEWER_PASSWORD>` | The demo's viewer login, also entered in the "Sign-in required" fields. |
| `<SHARE_LINK>` | The demo's share link, `<DEMO_URL>/#token=<token>`. It expires 14 days after the demo is regenerated, so regenerate it before every submission. |

Before submitting: regenerate the demo archive, check that `<DEMO_URL>/api/health` answers, sign in once with the login and once with the link, tick "Sign-in required", and attach the screen recording under App Review Information > Attachment.

## Notes

1. Screen recording. Attached. It starts at app launch and shows: entering the server address, signing in with the viewer account, browsing the chat list, opening a thread, opening a photo, searching and opening a result, opening the share link with downloads off, and signing out.

2. Purpose and audience. TG Archive is the iOS client for Telegram-Archive, an open-source server that people run themselves to keep a backup of their own chat history. The app lets them read that backup on their iPhone. It is read-only and shows only the archive on the server the user enters, with the access that server grants to the login.

3. Setup and access. Normally the user installs the server (https://github.com/GeiserX/Telegram-Archive), enters its address in the app, and signs in with a viewer account or pastes a share link. For review, use our demo server, which holds an invented archive:
   - Server address: <DEMO_URL>
   - Viewer account: username <VIEWER_USERNAME>, password <VIEWER_PASSWORD>
   - Share link (downloads are off for this link, so media shows a "Downloads are off for this login" tile): <SHARE_LINK>
   To try the share link: in Settings tap Sign Out, choose "Share link" on the sign-in screen, and paste the link. On a fresh install, copying the link and tapping Paste under "Have a share link?" on the first screen does the same.

4. External services. The app talks only to the server the user enters and controls. It never contacts any other service; the server uses the Telegram API to make the backup. No analytics, ads, purchases or tracking. Accounts are created and deleted by the server's owner on the server, so in-app account deletion (5.1.1(v)) does not apply, and there is no third-party social login, so Sign in with Apple (4.8) does not apply.

5. Regional differences. None. The app works the same in every region.

6. Regulated or third-party content. Not applicable: the app shows only the user's own private backup from their own server. There is no posting, no feed, no discovery and no contact between app users, so 1.2 does not apply.

Native functionality (4.2): there is no web view. Chats, threads and search are native SwiftUI lists with Dynamic Type, dark mode and VoiceOver labels; photos open in a zoomable viewer, video and audio play through AVKit, documents open in Quick Look, locations show in MapKit, the session lives in the Keychain, and files go through the share sheet.

TG Archive is part of the open-source Telegram-Archive project and is independent of Telegram; the server you run uses the Telegram API. Source code: https://github.com/GeiserX/TG-Archive-iOS
