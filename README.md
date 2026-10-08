<h1 align="center">
  <img src="docs/images/banner.svg" alt="TG-Archive-iOS" width="900"/>
</h1>

TG Archive is the iOS client for [Telegram-Archive](https://github.com/GeiserX/Telegram-Archive), the open-source server you run yourself to back up your chats. Point it at your server, sign in with a viewer account or a share link, and read, search and open your archived chats natively on the iPhone.

TG Archive is part of the open-source Telegram-Archive project and is independent of Telegram; the server you run uses the Telegram API.

Status: v0.1.0 is being prepared for TestFlight and the App Store.

## Features

- **Your server, nothing else.** The app talks only to the address you enter, through the server's [documented API](https://github.com/GeiserX/Telegram-Archive/blob/main/docs/reference/api.md). No analytics, ads or tracking ([privacy policy](PRIVACY.md)).
- **Three ways in.** A viewer account, a pasted share link, or nothing at all when the server runs in anonymous mode.
- **Chat list.** Previews, folders, archived chats, forum topics, server-side title search, pull to refresh.
- **Every message kind.** Formatted text, replies, forwards, reactions, polls, locations, venues, contacts, stickers, pinned messages, service rows, and marks for messages that were edited or deleted after the backup saved them.
- **Media.** Zoomable photos, videos and round videos through AVKit, voice notes and audio with their transcripts, documents in Quick Look, and the share sheet when the login allows downloads.
- **Search.** Every message the login can see, with a jump to the hit inside its chat.
- **One clean session.** The session cookie lives in the Keychain on this device. The app holds one server session and ends it when you sign out, so it never pushes out a browser session.
- **Native.** SwiftUI, Swift 6, iOS 18, iPhone, English and Spanish, no third-party packages, no web views.

## Quick start

1. Run a Telegram-Archive server with its viewer enabled. Its [documentation](https://github.com/GeiserX/Telegram-Archive) covers the install, viewer accounts and share links. A server outside your local network needs https.
2. Install TG Archive (TestFlight and App Store links will be here once it ships), or build it as below.
3. Enter your server's address, or paste a share link, and sign in.

### Build from source

You need a Mac with Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/GeiserX/TG-Archive-iOS.git
cd TG-Archive-iOS
brew install xcodegen
xcodegen generate          # writes TGArchive.xcodeproj from project.yml
open TGArchive.xcodeproj
```

Run the tests on a simulator:

```bash
xcodebuild test -project TGArchive.xcodeproj -scheme TGArchive \
  -destination "platform=iOS Simulator,id=$(scripts/pick-simulator.sh)" \
  -parallel-testing-enabled NO
```

### Try it without your own archive

`scripts/demo-server.sh start` runs a demo Telegram-Archive viewer on `http://127.0.0.1:8000` with an invented archive, and prints its logins and share link. It needs `git` and `uv` (`brew install uv`). `stop`, `status` and `reset` do what they say.

## Documentation

- [Design](docs/DESIGN.md): the screens, the API routes each one uses, the session rules and the App Review plan.
- [Agent and contributor notes](AGENTS.md): how to build, test and land a change.
- [App Store text](docs/app-store/): the store name, subtitle, keywords and description in English and Spanish, and the App Review notes template.
- [Privacy policy](PRIVACY.md) and [security policy](SECURITY.md).
- [Telegram-Archive API reference](https://github.com/GeiserX/Telegram-Archive/blob/main/docs/reference/api.md).

Releases: merge to `main`, wait for CI on that commit, then push a tag `vX.Y.Z` that matches `MARKETING_VERSION` in `project.yml`. [`release.yml`](.github/workflows/release.yml) archives, signs and uploads the build to TestFlight.

## License

GPL-3.0-or-later with an App Store distribution permission; see [LICENSE](LICENSE) and [NOTICE](NOTICE). Source: https://github.com/GeiserX/TG-Archive-iOS
