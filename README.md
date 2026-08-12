# The SESH.

The SESH. is a privacy-minded cannabis companion for adults. It combines session journaling, mood and strain tracking, stash awareness, personal insights, music memories, and optional social/community features in a native SwiftUI app.

Current app version: **59**. The project targets **iOS/iPadOS 26** and includes the main app, a widget, Live Activities, deep links, local persistence, and optional Unified Worker services.

The app is for responsible use where cannabis is legal. It does not provide medical advice, facilitate buying or selling, or replace local law or professional guidance.

## Product capabilities

### Sessions, journal, and insights

- Start, track, finish, and save a session with activity, strain, amount, method, mood, setting, people, and notes
- Active-session experience, quick actions, reusable flows, timers/Live Activity, and deep links
- Private thoughts and journal history with favorites, reliability categories, ratings, cost, and contextual details
- Recaps, journey records, trends, cost analytics, tolerance planning, goals, streaks, and personalized insights
- On-device intelligence where available, with privacy-preserving fallback behavior

### Strains and stash

- Bundled strain catalog, search, comparison, matching, notes, imagery, and effect intelligence
- Stash quantities, wishlist, favorites, forecasting, spending context, and restock awareness
- Mood/activity matching and post-session feedback to make future suggestions more personal

### Music and memories

- Apple Music and optional Spotify connections
- Session-linked listening memories, playlists, scrobbling, and music-aware recap experiences
- Provider failure must not prevent a session or journal entry from being saved

### Community

- Optional identity, friend codes, friendships, status/activity, and QR friend cards
- Cyphers, rooms, realtime chat, lounge feed, posts, reactions, polls, media previews, and journey sharing
- Blocking, reporting, audience controls, moderation categories, privacy settings, and offline outbox retry
- Push notifications and WebSocket-based realtime updates through the Unified Worker

## Application structure

The adaptive root experience is organized around Home, Explore, Journal, Community, and Profile-style destinations, with shortcuts for starting/logging a session, recording a thought, music, status, strains, and social activity. Features should degrade to private/local behavior when community services are unavailable.

| Area | Key implementation |
| --- | --- |
| App lifecycle and shell | [`The SESH./MoodWeedJournalApp.swift`](The%20SESH./MoodWeedJournalApp.swift), [`The SESH./CoreUI/RootView.swift`](The%20SESH./CoreUI/RootView.swift) |
| Session lifecycle | [`The SESH./Session/`](The%20SESH./Session/) |
| Persistence and domain models | [`The SESH./Persistence/`](The%20SESH./Persistence/) |
| Journal and insights | [`The SESH./Journal/`](The%20SESH./Journal/), [`The SESH./Features/`](The%20SESH./Features/) |
| Strains and stash | [`The SESH./Strains/`](The%20SESH./Strains/), [`The SESH./Stash/`](The%20SESH./Stash/) |
| Music | [`The SESH./Music/`](The%20SESH./Music/) |
| Social and lounge | [`The SESH./Social/`](The%20SESH./Social/), [`The SESH./Lounge/`](The%20SESH./Lounge/) |
| Networking | [`The SESH./Networking/`](The%20SESH./Networking/), [`The SESH./UnifiedWorker.swift`](The%20SESH./UnifiedWorker.swift) |
| Widget and tests | [`SeshWidget/`](SeshWidget/), [`SeshTests/`](SeshTests/) |

Local persistence is authoritative for private session and journal work. Network synchronization, social state, push, Spotify authorization, and QA reporting are additive services.

## Requirements

- macOS with [Xcode](https://developer.apple.com/xcode/) and the iOS 26 SDK
- An Apple development team for signed physical-device builds
- Correct Sign in with Apple, push notification, App Group, widget, Live Activity, and Keychain capabilities for enabled features
- Optional access to the [Unified Worker](https://github.com/sahmoee/UnifiedWorker)
- Optional Apple Music/Spotify accounts for their respective integrations

## Setup and build

```bash
git clone https://github.com/sahmoee/The-Sesh.git
cd The-Sesh
open "The SESH..xcodeproj"
```

Select the **The SESH.** scheme, assign the correct development team to the app and widget, choose a connected device, and run.

Generic physical-device verification:

```bash
xcodebuild \
  -project "The SESH..xcodeproj" \
  -scheme "The SESH." \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

## Configuration and integrations

The app’s shared backend route is `https://api.sowensstudios.com/sesh`. Legacy released builds remain supported through the `sesh-worker` compatibility shim documented in the [Unified Worker migration guide](https://github.com/sahmoee/UnifiedWorker/blob/main/MIGRATION.md).

| Integration | Client responsibility | Server responsibility |
| --- | --- | --- |
| Sign in with Apple | User authorization and identity token | Session verification/signing |
| Social/rooms/lounge | UI, local cache, offline outbox | Durable social graph, rooms, feed, WebSockets |
| Push notifications | Permission and device token | APNs signing and delivery |
| Spotify | Authorization handoff | Client secret and refresh-token exchange |
| DeviceCheck | Device attestation payload | Apple verification and enforcement |
| QA | Local ticket/screenshot queue | Validation and report storage |

Server credentials—including APNs `.p8`, Spotify client secret, DeviceCheck key, session secret, and admin key—must be stored as Cloudflare secrets and never added to the Xcode project. See the Worker’s [`SECRETS.md`](https://github.com/sahmoee/UnifiedWorker/blob/main/SECRETS.md).

## Data, privacy, and offline behavior

- Session and journal creation must succeed locally even without an account or network.
- Social actions can enter [`The SESH./Networking/OfflineOutbox.swift`](The%20SESH./Networking/OfflineOutbox.swift) and retry when connectivity returns.
- Cloud/sync code must preserve local edits, explicit visibility, blocks, and audience settings.
- Media, personal notes, health-adjacent observations, and precise usage history are sensitive user data.
- The app must not imply medical outcomes or recommend unsafe, illegal, underage, driving, or purchasing behavior.

## Testing and QA

Core tests are in [`SeshTests/`](SeshTests/). Changes should cover domain transformations, persistence compatibility, session lifecycle, social safety/privacy, and networking fallbacks as relevant. Test on a physical iPhone for notifications, Live Activities, music authorization, camera/QR behavior, and realtime features.

Internal QA reports save locally first, then synchronize with screenshot and build/device context. Fixed reports require a “What was fixed” explanation. Testers choose **Verify Fix** or **Refile — still broken**, preserving ticket history and adding current evidence.

Shared intake is under `~/Documents/Reports/Sesh`. Coding agents must follow [`AGENTS.md`](AGENTS.md) before planning, changing, or building.

## Release checklist

- Update [`CHANGELOG.md`](CHANGELOG.md) and [`The SESH./Profile/AppChangelog.swift`](The%20SESH./Profile/AppChangelog.swift).
- Confirm marketing/build versions for the app and widget.
- Run tests and a generic-device build, followed by physical-device verification.
- Verify onboarding/age messaging, private logging, data migration, offline behavior, Apple/Spotify flows, push, social privacy, blocks/reports, rooms, lounge, widget, and Live Activity.
- Review [`PRIVACY.md`](PRIVACY.md), [`SECURITY.md`](SECURITY.md), privacy manifest, third-party notices, and [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).
- Archive with Xcode and distribute through TestFlight before production submission.

## Troubleshooting

- **Social or chat is unavailable:** check connectivity, authentication, Worker health, WebSocket reachability, and the offline outbox.
- **Push does not arrive:** verify notification permission, device-token registration, APNs environment, key/team/bundle configuration, and background settings.
- **Spotify connection fails:** verify server-side client credentials and redirect flow; do not embed the Spotify secret in the app.
- **A session appears missing:** inspect local persistence/storage health before attempting cloud resets or deleting app data.
- **Widget/Live Activity is stale:** verify the shared App Group, extension signing, system permissions, and activity lifecycle.

## Safety, security, legal, and support

Never commit tokens, Apple keys, journals, social exports, user media, or QA screenshots. Use platform-protected storage on device and provider secret stores on the server. See [`PRIVACY.md`](PRIVACY.md), [`SECURITY.md`](SECURITY.md), [`SUPPORT.md`](SUPPORT.md), and [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).

## Contributing and license

- [`CONTRIBUTING.md`](CONTRIBUTING.md) — development expectations
- [`AGENTS.md`](AGENTS.md) / [`CLAUDE.md`](CLAUDE.md) — agent and report workflow
- [`CHANGELOG.md`](CHANGELOG.md) — release history
- [`LICENSE.md`](LICENSE.md) — license terms

Preserve private/local functionality, persisted-data compatibility, moderation and audience controls, and backward-compatible Worker contracts. Add regression coverage and update all affected projects when a shared contract changes.
