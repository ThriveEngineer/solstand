# Solstand Mail

A native macOS email client built in Swift and SwiftUI. Solstand Mail connects to the accounts you already use and keeps a local cache so reading and organizing mail remains quick and available offline.

## Product direction

The interface combines Notion Mail's restrained workspace feel, configurable inbox views and keyboard-first navigation with Canary Mail's broad account support, focused inbox workflows, privacy controls and optional AI assistance.

## Features

- **Bring your own account.** Gmail, Outlook, iCloud, Yahoo, Fastmail, and other IMAP/SMTP providers. OAuth sign-in is available for Outlook when configured; other providers may require an app password.
- **Unified inbox.** View accounts together or individually, with custom inbox views, tabs, folders, unread and flagged filters.
- **Offline-first.** Mail is cached locally; reading, searching and queued actions continue when a connection is unavailable.
- **Focused workflows.** Archive, delete, mark as junk, flag, move to folders, unsubscribe, prioritize VIP senders, and snooze mail locally until tomorrow or next week.
- **Thoughtful writing.** Rich text composition, attachments, replies and forwards, templates, quick replies, undo and redo.
- **Private reading.** Remote images are blocked by default, message HTML is sanitized, and the original message is available for inspection.
- **Optional AI.** Connect a provider of your choice for drafting, thread summaries and inbox assistance. AI never sends mail; drafts remain for review in the composer. AI requests may include the email content needed for the requested task.
- **macOS integration.** Notifications, Dock unread count, light and dark appearances, and keyboard shortcuts.

## Research notes

The product direction was informed by current public product material from [Notion Mail](https://www.notion.so/product/mail), [Canary Mail](https://canarymail.io/features), and the [Canary Mail macOS preferences guide](https://canarymail.io/help/macos-preferences). The implementation keeps the native mail-client foundation while removing the original service-specific sign-in, license checks, branded upgrade surfaces, and the updater tied to the upstream repository.

## Build

Requires macOS 15.3 or later and Xcode 16+. This project already references the `MailflareCore` Swift package at `../mailflare-core`. Clone and build that package before opening the project:

```sh
cd ..
git clone https://github.com/hieunc229/mailflare-core.git
cd mailflare-core
./scripts/build-ios.sh --macos
cd ../solstand
open Mailflare.xcodeproj
```

If you already cloned the package, run `./scripts/build-ios.sh --macos` from its directory instead. The script builds the generated XCFramework required by `Package.swift`, including a macOS slice. Then run the **Solstand Mail** scheme in Xcode. The app no longer exposes Mailflare account sign-in or workspace licensing. Set `SOLSTAND_MAIL_OAUTH_MICROSOFT_CLIENT_ID` to your own Microsoft Entra application ID (redirect `msauth.com.solstand.mail://auth`) to enable Outlook OAuth. The code and UI are Swift and SwiftUI.

## Privacy

Account credentials and AI provider keys are stored in the macOS Keychain. Mail is cached on this Mac. Mail content is sent only to the connected mail provider, and to the AI provider when you choose an AI feature.

## License

GNU AGPL v3. See [LICENSE](LICENSE).
