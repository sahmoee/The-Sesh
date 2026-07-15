# The SESH — Batch 1 Implementation

First implementation batch: **Code 1, 2, 9, 12, 19** and **Connectivity 1, 3, 4, 5, 9** — the largest security, data-loss, concurrency, scaling, and reliability risks.

Every file in this package keeps its project-relative path. Drop the `The SESH.` and `_worker` contents over your project (or diff first), then follow the deploy steps below.

---

## Code batch

### Code 1 — Swift 6 (`project.pbxproj`)
`SWIFT_VERSION = 5.0 → 6.0` on all four configurations, plus `SWIFT_STRICT_CONCURRENCY = complete` at the project level so both the app and widget targets build with full checking. `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` was already set on the app target, which keeps the migration surface small. Expect a handful of new diagnostics on first build — they are real data races the compiler is now allowed to reject.

### Code 2 — `SocialStore` is `@MainActor` (`SocialStore.swift`)
The store mutates `@Observable` UI state from polling tasks, chat sends, push registration, and now realtime events. Explicit isolation makes every mutation compiler-checked instead of convention-checked.

### Code 9 — No more `replaceAll` on every save (`Persistence.swift`, `Models.swift`)
New `SeshDataStore.sync(entries:thoughts:)` reconciles record-by-record: upserts changed records in place, deletes only removed ones, and saves only when the context has changes. `AppSession.save()` and `mergeFromStorage()` now call it. `replaceAll` survives only for the one-time UserDefaults→SwiftData migration into an empty store.

### Code 12 — Stable strain image assignment (`StrainImageStore.swift`)
`bundledBud(for:)` now hashes with FNV-1a over UTF-8 bytes. `String.hashValue` is per-process seeded, so every launch previously reshuffled all strain photos.

### Code 19 — Project configuration normalized (`project.pbxproj`, entitlements)
- iOS deployment target mismatch resolved: project-level `26.2 → 26.0` (matching the app target).
- `The SESH.Release.entitlements`: `aps-environment development → production` (release/TestFlight/App Store builds always use production APNs).
- `TheSESH.entitlements` (Debug) now carries the full capability set (APNs *development*, iCloud, app groups) so Debug and Release entitlements only differ where they must.
- **Manual step:** delete the now-redundant duplicates from the repo — the root-level `TheSESH.entitlements` and `The SESH./The SESH..entitlements`. The pbxproj references only `The SESH./TheSESH.entitlements` (Debug), `The SESH./The SESH.Release.entitlements` (Release), and `SeshWidgetExtension.entitlements`.

---

## Connectivity batch — Worker rewritten as modular TypeScript

`_worker/sesh-worker/src/` is now: `index.ts` (router) + `auth.ts`, `apns.ts`, `spotify.ts`, `social.ts` (SocialDO), `rooms.ts` (RoomDO), `util.ts`. The old `index.js` is a fail-loud stub. `npx tsc --noEmit` passes.

### Connectivity 1 — Server-side authentication
- `POST /api/auth/apple {identityToken}` — verifies the Sign in with Apple token against Apple's JWKS (RS256 signature, iss, aud=`APPLE_BUNDLE_ID`, exp) and issues a 24 h HMAC-signed session token bound to the Apple `sub`.
- `POST /api/auth/guest {deviceID}` — session for "continue without signing in" (App Attest is the follow-up hardening, backlog C2).
- Every other endpoint requires `Authorization: Bearer` and uses **only** the verified uid — the spoofable `x-sesh-*` headers and body identity fields are gone.
- Client: new `SeshAuth.swift` (Keychain-stored token, silent re-exchange on 401), `AppleAuth.swift` exchanges the identity token on sign-in, `SeshAPI.swift` attaches the Bearer header and retries once after a refresh.

### Connectivity 3 — WebSockets replace 12-second polling
- `GET /api/ws` (SocialDO, hibernation API): the server pushes `{type:"changed"}` whenever social state mutates; the app pulls one snapshot in response. Heartbeats ride the socket.
- `GET /api/rooms/:id/ws` (RoomDO): live message stream per room.
- Client: new `SeshRealtime.swift` — reconnects with exponential backoff + jitter; `SocialStore` keeps a 60 s slow poll as a safety net while the socket is down.

### Connectivity 4 — Shared KV blobs partitioned
- **SocialDO** (single instance) owns users, friendships, blocks, cyphers, live, feed — one storage record per user (`user:<uid>`), a `code:<CODE>` index for friend codes, and serialized writes, eliminating the read-modify-write races on the old `users`/`blocks` KV blobs.
- **RoomDO** (one per room) stores one record per message (`msg:<sentAt>:<id>`), giving keyed pagination and race-free concurrent sends; per-user rate limiting is in-DO and strongly consistent.
- KV remains only for Spotify refresh tokens (single-key, single-writer) and legacy data during migration.
- Blocking a user now also severs the friendship in both directions.

### Connectivity 5 — Offline outbox
- Client: new `OfflineOutbox.swift` — persisted (Application Support), bounded queue; replays oldest-first with exponential backoff + jitter; drops permanently-failed ops. Chat sends and activity/status posts route through it (message id doubles as idempotency key).
- Server: every write accepts `X-Idempotency-Key`; SocialDO and RoomDO record processed keys (24 h) and acknowledge duplicates without re-applying.

### Connectivity 9 — Push token lifecycle
- `apns.ts` surfaces APNs failures: HTTP 410 / `BadDeviceToken` / `Unregistered` / `DeviceTokenNotForTopic` mark the token dead; the router prunes it from the owning user via `POST /push/prune`. Failures are logged with status + reason.
- Sign-out (`ProfileView` → `SocialStore.signOut()`) unregisters the device token, closes the realtime socket, and drops the session; `AuthManager.signOut()` clears the Keychain session.
- Entitlements now match APNs environments per configuration (see Code 19); `APNS_USE_SANDBOX=1` is available for a dev worker paired with Xcode debug builds.

---

## Deploy steps

1. **Xcode**: add the three new files (`SeshAuth.swift`, `OfflineOutbox.swift`, `SeshRealtime.swift`) to the app target; build and burn down any new Swift 6 strict-concurrency diagnostics.
2. **Worker**:
   ```
   cd _worker/sesh-worker
   npm install
   wrangler secret put SESSION_SECRET      # long random string
   wrangler deploy                          # runs the v1-durable-objects migration
   ```
   Existing secrets (APNs, Spotify) carry over. `ADMIN_KEY` still guards `/api/admin/export`.
3. **Data migration**: the old KV blobs (`users`, `rooms`, `msgs_*`, …) are not auto-migrated. Either start fresh (the social data is early-stage) or write a one-shot script that reads the KV blobs and POSTs them into the DOs. KV keys `sp_refresh_*` keep working unchanged.
4. **Repo hygiene**: delete root `TheSESH.entitlements`, `The SESH./The SESH..entitlements`, and (once CI is updated) `_worker/sesh-worker/src/index.js`.

## Notable behavior changes
- Unauthenticated requests now get 401 — old app builds cannot talk to the new Worker. Deploy the app and Worker together (or stand up a second Worker for staging first — backlog item C10).
- Seeded fake community users are gone from the Worker; empty states show until real users appear.
- `feed` events now carry `userID`, so block filtering works on events (it silently didn't before).

---

# Batch 3 + 4 (applied directly to this project)

## Batch 3
- **App 18 — Age gate + responsible use** (`SafetyAndPrivacy.swift`, `RootView.swift`, `Models.swift`): 21+ full-screen gate on first launch (impairment/no-driving/privacy acknowledgements); opt-in water/check-in reminders that follow the live sesh (scheduled in `saveLiveSesh`, cancelled in `clearLiveSesh`); Responsible Use screen — no medical claims.
- **App 16 — Privacy controls** (`SafetyAndPrivacy.swift`, `SocialStore.swift`): per-field toggles (activity, strain details, music, session duration, live status, friend-code discoverability), persisted and *enforced* — `setMyActivity` skips the broadcast when activity sharing is off and strips strain detail when strain sharing is off; `setNowPlaying` stays local when music sharing is off.
- **App 17 — Moderation UX** (`SafetyAndPrivacy.swift`): categorised `ReportSheet` (harassment / underage / selling / spam / dangerous use / other + details), `blockConfirmation(...)` confirm dialog (block also unfriends both ways, server-side since Batch 1), visible `CommunityRulesView` with appeal contact.
- **Profile wiring** (`ProfileView.swift`): "Privacy & Safety" entry in Settings → hub with all three screens.
- **C10 — Environments** (`BuildConfig.swift`, `wrangler.toml`): Debug builds can point at a dev Worker via the `sesh.dev.workerURL` UserDefaults override; `[env.dev]` / `[env.staging]` wrangler environments with separate Workers, DOs, secrets, and sandbox APNs. Deploy with `wrangler deploy --env dev`.

## Batch 4
- **Code 6 — Typed request bodies** (`SeshAPI.swift`, `SocialStore.swift`): generic `post(_:body:)` over `Encodable`; activity, chat messages, push register/unregister, friend-add, and block/unblock now use typed structs (`ActivityBody`, `MessageBody`, `TokenBody`, `FriendCodeBody`, `TargetUserBody`); outbox enqueues encode the same types. Remaining `[String: Any]` call sites are the Spotify export payload and the legacy overload, kept for endpoints not yet migrated.
- **Code 8 — Task ownership** (`SocialStore.swift`): `teardown()` centrally cancels polling, the realtime socket, the vibing-fade timer, and outbox replay; sign-out uses it.

## Repairs (this session)
- Restored `Assets.xcassets` entries wiped by a Finder "Replace" during batch extraction (AppIcon, AccentColor, catalog Contents.json, 80+ imagesets) and the shared Xcode schemes — all from your original archive, no batch changes overwritten.

## Xcode step
Add **`SafetyAndPrivacy.swift`** to the app target (plus the Batch 1/2 files if not done yet: SeshAuth, OfflineOutbox, SeshRealtime, ConnectivityMonitor, SocialCache, Diagnostics, ConnectivityBanner).

## Deliberately not auto-applied (needs a compiler + review, happy to do next)
Code 3/4 (file splits & feature folders), 5 (dependency injection), 10/11 (UserDefaults→SwiftData, CloudKit records), 13 (shared image pipeline), 14 (navigation coordinator); App 1/2 (session-aware Home + quick actions), 10 (accessibility pass), 12 (iPad layouts); and the Features list. These reshape live UI/persistence code — doing them blind risks breaking your build in ways a zip can't fix.
