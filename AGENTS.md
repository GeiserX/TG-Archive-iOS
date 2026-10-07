# tg-archive-ios: agent notes

TG Archive is an unofficial, read-only iPhone client for a self-hosted
[Telegram-Archive](https://github.com/GeiserX/Telegram-Archive) server. SwiftUI, Swift 6, iOS 18, no
third-party packages. The one design the code follows is [docs/DESIGN.md](docs/DESIGN.md); read it
before changing anything.

## Layout

- `project.yml`: the XcodeGen spec and the single source of truth. The `.xcodeproj` is generated and
  never committed.
- `TGArchive/`: the app. `TGArchiveTests/`: unit tests (Swift Testing) with JSON fixtures captured from
  the demo server. `TGArchiveUITests/`: UI tests (XCTest) that run against the demo server.
- `scripts/`: the simulator picker, the Required Reason API check, the demo server and the fixture capture.

## Build and test

Builds, tests, simulators and the demo server run on a Mac with Xcode, never on the laptop you edit on.

```bash
brew install xcodegen
xcodegen generate                                  # writes TGArchive.xcodeproj from project.yml
xcodebuild test -project TGArchive.xcodeproj -scheme TGArchive \
  -destination "platform=iOS Simulator,id=$(scripts/pick-simulator.sh)" \
  -parallel-testing-enabled NO
scripts/check-required-reason-apis.sh --self-test && scripts/check-required-reason-apis.sh
```

- From an editing laptop, run `scripts/mini-test.sh`. It copies the checkout over ssh to the Mac named by
  `MINI_HOST`, generates the project, runs the unit and UI tests on a simulator and applies the same
  test-count gate as CI. The script's header lists its other settings.
- `scripts/demo-server.sh start|stop|status|reset` runs a demo Telegram-Archive viewer on
  `127.0.0.1:8000` with invented data, for the UI tests and the store screenshots
  ([docs/DESIGN.md](docs/DESIGN.md) section 5). `scripts/capture-fixtures.sh` refreshes the unit-test
  fixtures from a running demo.
- CI (`.github/workflows/ci.yml`) runs the unit and UI tests, a test-count gate, the Required Reason API
  check and a Release build. When you add tests, raise the count in the gate.

## How changes land

- Every change lands through a pull request, and only once the required "Build and test" check is
  green. `main` takes no direct pushes. Pull requests are never drafts.
- Conventional commits. Actions are pinned to a commit SHA.
- A gate you add must be able to fail: show it red once, with a broken input or a negative control.

## File ownership

Implementation runs in stages, listed in [docs/DESIGN.md](docs/DESIGN.md) section 8, and each stage owns
its files. Stages that run at the same time never touch the same file. A stage edits another stage's file
only where section 8 says so. When a fact in the design turns out wrong, the stage fixes it with a
one-line note in that document.

## Naming and disclosure

- The app is "TG Archive" everywhere: display name, store name, About screen. "Telegram" is never part
  of the app name, subtitle, keywords, bundle id or icon.
- The icon is the Telegram-Archive mark, the same as the server project's. Never Telegram's own logo,
  in the icon or anywhere else.
- The store description and the About screen carry the unofficial disclosure from
  [docs/DESIGN.md](docs/DESIGN.md) section 1, word for word.
- Nothing in this repository names a private server, hostname, person or deployment: not in code, docs,
  fixtures, commit messages or pull requests. Write "your server" or "the demo server". Review
  credentials and the public demo address live only in App Store Connect.

## License

GPL-3.0-or-later with the App Store distribution permission in `NOTICE`.
