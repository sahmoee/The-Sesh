# The SESH. Apple Watch companion — September 14, 2026

## Delivered scope

This is a native, embedded watchOS 26 companion for the existing iOS/iPadOS 26 app. It uses a compact dark interface, the existing SESH icon and muted green accent, native scrolling/forms/pickers, readable status text and privacy-sensitive note surfaces. It does not require a new Worker, server, subscription, account token, social login or cloud schema.

| Watch entry point | Implemented behavior |
| --- | --- |
| Home → Log session | Saves private strain, method, rating, optional mood, amount/unit, date, notes, session tag and before/after mood. Complete numeric parsing rejects malformed pasted values. |
| Home → Start session / Resume timer | Local elapsed timer survives restarts; review and save creates one private iPhone log with bounded duration. Discard is explicit. An existing iPhone live session is displayed separately with an instruction to finish it on iPhone. |
| Home → Journal | Recent offline history and session details, favorite/unfavorite, pin/unpin in Journal Studio, and log-this-strain-again. Pending flag changes remain clearly identified until iPhone acknowledgement. |
| Home → Thoughts | New private thoughts, recent thoughts and searchable full-history pages. Nothing is posted to Community. |
| Home → Stash | Offline quantities, cost and dates; add a purchase; log from a specific stash item. The phone checks strain, unit and remaining quantity and commits the log, deduction and receipt together. Explicit new-strain logging clears an old draft's stash link; intentional resume displays that link and offers unlink. |
| Home → Strains | Relevant cached catalog records, potency/reference descriptions, full iPhone catalog search and pagination, and log a selected strain. Catalog descriptions are not predictions or medical advice. |
| Home → Goals | Active/paused goals, current calendar-week recorded sessions/spending versus personal limits, create goals, and pause/resume. Targets describe user choices, not suggested consumption or health outcomes. |
| Each section → Browse all | Searches the full iPhone history/catalog/stash/goals/thought collection, returning 20-record pages. This explicitly requires reachable iPhone; the offline cache is labeled as limited. Long note excerpts are limited to 500 characters; originals remain on iPhone. |
| Home / Settings → Pending | Durable command count, individual payload review, terminal/retryable errors, explicit retry and individual removal. Removal warns that an already-delivered action may still save; check iPhone before recreating it. |
| Settings | Last-copy timestamp, reachable/offline status, refresh, haptics, hide private thought/entry/goal notes, retry unreadable storage and explicit watch-cache/draft/outbox erase. |
| iPhone Profile → Settings → Apple Watch | Enables/disables paired access, refreshes the copy, exposes connection/recovery information, and explains offline/reset limits. |

Incomplete log amounts, thoughts, stash amounts/costs, and goal targets/notes are saved as drafts, including unfinished numeric text. Saving a command clears only the corresponding draft after the queue file commits. Data unavailable on the Watch is explained: social/community, music-account connections, photo/media imports, full notes and notebook editing stay on iPhone. These are honest instructions to open the phone app, not fake remote-open or publication actions. Complications and standalone cloud access are not included.

## Ownership and contracts

- **Owner:** The-Sesh. `WatchShared/SeshWatchContract.swift` is the sole v1 wire contract; `SeshWatchStorage.swift` owns the cache/outbox and correlated request gate.
- **Producer/consumer pair:** `SeshPhoneWatchBridge` produces snapshots/pages/receipts and consumes commands. `SeshWatchStore` consumes them and produces commands/foreground read requests. No other app consumes this channel.
- **Channel:** `com.sowens.sesh.watch.v1`; each packet contains channel and protocol version. Phone and Watch validate bounded types, dates, amounts, text, IDs and page offsets before use. Unsupported versions fail visibly rather than interpreting another schema.
- **Authoritative state:** Existing iPhone journal/stash/goal stores. Watch snapshots are private local copies, never an independent journal replacement. Watch commands use stable UUIDs and the phone journal epoch.
- **Queue:** At most 100 commands. Capacity rejects the new command without evicting any old one. A file must commit atomically before the UI says queued. Acknowledgements match command UUID and epoch; duplicate/unrelated receipts cannot remove other actions.
- **Delivery:** WCSession activates before onboarding/social bootstrap. Delegate callbacks hop to the main actor. Background command transfer and optional interactive delivery may both deliver the same UUID; the phone handles this idempotently. Read-only refreshes are coalesced interactive requests, not persistent background transfers. Snapshot and page waits time out after 20 seconds; stale request replies are ignored. Background watchConnectivity work waits for session activation, system pending content and accepted callback writes to drain, with cancellation.
- **Idempotent commits:** `SeshWatchTransactions` uses a private SwiftData context, SHA-256 of sorted command JSON and `SDRecord` receipts. Log/thought/favorite/purchase mutations and receipts commit in the same context; linked stash deduction shares the log transaction. A replay with the same UUID and payload returns its stored receipt, while altered payloads are rejected. Terminal missing-target/stash conflicts also persist a rejected receipt so that UUID cannot later succeed. Transient storage failures remain retryable. The 20,000-receipt ceiling stops new writes without deleting deduplication history.
- **Goal/pin exception:** Goals and Studio pins already have separate protected-file owners. Exact flag assignment and stable goal identity make retry safe if the app stops between their file commit and receipt commit. These are not claimed to be one multi-file transaction. Recreated goal IDs with different content are rejected. Existing goal/Studio persistence errors remain authoritative.
- **Existing iPhone consumers:** After a successful private transaction, AppSession refetches actual store rows before publishing changes or running its existing private cloud mirror. Original domain records and SwiftData schema 1.2.0 remain compatible. Private Watch transport does not add a social write. Studio pins retain their existing device-local-only contract.

## Storage, privacy and recovery

The phone keeps `Application Support/WatchCompanion/phone-state.json`; the Watch keeps `WatchCompanion/private-state-v1.json`. The protected atomic files are capped at 2 MiB. Corrupt, oversized or symlink files are preserved and block replacement until a successful reread or the user's explicit erase. Data uses complete file protection until first user authentication on iOS/watchOS. No credentials or private payloads are logged.

Application-context snapshots fit within 48 KB, and wire decoding/encoding is capped at 60 KB. Snapshots retain up to 40 entries, 35 stash records, 50 relevant strains, 25 goals and 15 thoughts, trimming further if the byte cap requires it. Typed maximums protect decode as well. Paged browsing supplies the rest while the iPhone is reachable. Notes are excerpts rather than silently edited originals; invalid historical rows that cannot satisfy the Watch contract are omitted from the projection, not deleted on iPhone.

Phone journal deletion rotates an epoch. The Watch trusts a foreign epoch only from its current correlated foreground handshake (or initial context when it has no prior copy). Within one epoch, only increasing revisions are accepted. Verified epoch change clears old private cached state, drafts, timers and queued commands and resets navigation/pages. Delayed contexts from an old epoch cannot bring data back. Disabling Watch access empties the phone-derived copy and exits old detail navigation. An unreachable Watch cannot be remotely cleared instantly: it clears after reconnecting and verifying the current phone state. Already-delivered requests can outlive a local Watch queue removal; the UI states that limit.

First release requires the new phone and Watch apps together. Existing iPhone-only installations keep working; no existing domain or Worker migration is needed. Rollback can remove the embedded Watch target and bridge while retaining all iPhone records already saved. Keep receipts/epoch files if a companion might be re-enabled; deleting them independently would remove replay protection. Watch files are not added to existing journal exports or a new iCloud backup contract.

## Targets and validation

- Shared scheme `SeshWatch`, native single watch app target `SeshWatch`, embedded under the iPhone app's `Watch/` directory.
- Phone bundle: `com.sowens.The-SESH-`; Watch bundle: `com.sowens.The-SESH-.watchkitapp`; exact `WKCompanionAppBundleIdentifier`, `WKApplication=true`, non-independent companion, family 4, watchOS 26.
- Existing project QA number reservation/stamping applies to both schemes and all embedded products. Marketing version remains **59**.
- Native production wire/storage fixtures: **82 checks passed**, including stale/duplicate receipts, 100-command persistence/overflow, dates/numbers, corrupt-file preservation, unfinished drafts, reset/reinstall epoch ordering, correlated stale responses and background callback drain tracking. Log: `/tmp/sesh-watch-native.log`.
- Native production-model SwiftData fixtures: **11 checks passed** using actual `SDJournalEntry`, `SDThought`, `SDRecord`, domain payloads and schema in a unique temporary store. They verify cross-context main refetch/retained-object updates, stash/receipt persistence and rollback. These are model/store checks, not an end-to-end `apply(command:)` or paired-delivery test. No application data is opened. Log: `/tmp/sesh-watch-persistence-native.log`.
- Generic unsigned watchOS build passed (`/tmp/sesh-watch-final-build.log`). Final iOS build, including the latest Watch sources and embedded widget, passed (`/tmp/sesh-ios-watch-final-build.log`). Built app, Watch and widget plists all report **59 (84)**; iPhone/Watch minimum OS is **26.0**. Embedded Watch metadata confirms native `WatchOS`, family 4, `WKApplication=true`, the exact companion ID and existing compiled icon assets.
- DerivedData: `/Volumes/Macintosh SSD/MacStorage/Developer/DerivedData/The_SESH.-gxjalgyywmslhvfgzwvfartdgdho`. Final phone artifact: `Build/Products/Debug-iphoneos/The SESH..app`; embedded companion: `Watch/SeshWatch.app`. Both shared scheme XML/project plist and `git diff --check` pass. The only final-build warning is the standard skipped AppIntents metadata extraction for a target without AppIntents dependency.
- No simulator, physical-device install, live Worker request, signing, TestFlight upload or social publication was performed.

Reproduce native checks from the repository root:

```sh
swiftc WatchShared/SeshWatchContract.swift WatchShared/SeshWatchStorage.swift scripts/WatchCompanionChecks.swift -o /tmp/sesh-watch-checks
/tmp/sesh-watch-checks
swiftc 'The SESH./Persistence/Models+Domain.swift' 'The SESH./Persistence/Persistence.swift' scripts/WatchPersistenceChecks.swift -o /tmp/sesh-watch-persistence-checks
/tmp/sesh-watch-persistence-checks
```

The persistence fixture supplies only unused theme/live-stage compilation adapters; the records and database schema under test are production sources. All fixture storage is disposable and uniquely named.

## Paired-device acceptance still open

`UnifiedQAProfile.sesh` contains eight stable `watch-*-v1` checks, all initially **untested**: first pairing/initial sync, offline command replay, stash deduction, timer/background delivery, full-library pagination, reset/delayed-packet isolation, drafts/storage recovery, and accessibility/privacy. The QA checklist must not mark these passed based on a source review or generic build. Actual paired hardware must validate WC background scheduling, reconnect/reboot delivery, no duplicate logs/deductions after retries, smallest/largest Watch layouts, VoiceOver, Crown navigation, Dynamic Type, haptics and privacy previews.
