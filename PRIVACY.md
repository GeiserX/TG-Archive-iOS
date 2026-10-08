# Privacy Policy: TG Archive for iOS

TG Archive is a read-only reader for a Telegram-Archive server that you run yourself. The app sends data only to the server you enter in it, and nothing to the developer. It has no developer server, no accounts of its own, no ads, no analytics and no tracking, and we never sell or share data.

## What the app sends, and where

- **To your server, and nowhere else.** The app talks only to the address you type or paste. It sends your username and password, or the share link's token, when you sign in, then the requests that read your chats, messages, media and search results. Everything it shows comes from that server.
- **Never to the developer.** The app contains no analytics, crash reporting, advertising or tracking code, and it makes no request to any address other than your server's. We never see your server's address, your login or your archive.
- **Never to Telegram.** The app does not contact Telegram. Your server made the backup; the app only reads it.

## What stays on your iPhone

- **The session.** After you sign in, the server's session cookie is kept in the iOS Keychain, on this device only and never synced. Your password and share token are never stored.
- **The last server address and username,** so the connect and sign-in screens can fill them in, and a marker that the app has run before. These are kept in the app's settings on this device.
- **A cache of media.** Photos, thumbnails and files you open are kept in the app's cache so they load faster. The app checks with your server each time before showing a cached copy.

Signing out ends the session on your server and removes the session, the cache and downloaded files from the iPhone. Settings also has Clear Cache. Deleting the app removes everything except the Keychain item, which the app removes the next time it is installed and opened.

## Your server

Your server's owner decides who can sign in, what each login can see, and how long sessions last. What your server records is governed by how its owner set it up, not by this app.

## Contact

Questions and requests: https://github.com/GeiserX/TG-Archive-iOS/issues

Last updated: October 2026.
