# The Sesh: 25 implemented reliability improvements

These are the core half of the fifty-change batch. Every item is used by current app behavior,
not an unused helper. Existing journal/session records, private photos, service endpoints, raw
Keychain token format and Worker message contracts remain intact.

## Implementation ledger

| # | Improvement | Source evidence |
| --- | --- | --- |
| 1 | GET retry loops stop on cancellation, including cancelled sleeps/URLSession calls. | Networking/SeshAPI.swift: sendWithRetry, send |
| 2 | Server Retry-After supports seconds and HTTP dates, rejects unsafe numbers and remains a minimum deadline. Long foreground cooldowns return the actual HTTP response; queued retries persist their deadline. | Core/SeshReliabilityPolicy.swift; SeshAPI; OfflineOutbox |
| 3 | Retry counts are bounded and final HTTP failures return without a pointless last sleep or a fabricated generic network error. | SeshAPI.sendWithRetry |
| 4 | Permanent/certificate/nontransport failures do not trigger repeated network attempts. | SeshReliabilityPolicy.transient; SeshAPI |
| 5 | Authenticated reads disable shared URL caching and pin account identity/generation across every attempt and await, preventing previous-account response reuse. | SeshAPI.sharedSession, send, sendWithRetry |
| 6 | Dynamic room/cypher/live identifiers are encoded as individual path segments; message-page limits are bounded. | SeshReliabilityPolicy.pathSegment; SeshAPI; SocialStore.send |
| 7 | JSON/media request construction enforces a 2 MB body limit before transmission; queued payloads also require valid JSON, bounded keys and local API paths. | SeshAPI.makeRequest; OfflineOutbox.enqueue |
| 8 | Fractional/plain ISO-8601 response dates use value-type parsing without crossing actors through shared mutable date formatters. | SeshReliabilityPolicy.serverDate; SeshAPI.decoder |
| 9 | Equal idempotency keys deduplicate only identical same-owner operations; conflicting duplicates fail visibly instead of double-appending. | OfflineOutbox.enqueue |
| 10 | Queue capacity rejects the new action instead of silently deleting the oldest unsent action. Chat keeps the unsaved draft. | OfflineOutbox.enqueue; SocialStore.send |
| 11 | Retry exhaustion and permanent request failures hold the original action for review instead of erasing it; restored extreme attempt counters cannot overflow. | OfflineOutbox.scheduleReplay |
| 12 | Replay generations and acknowledged record identity protect queue removal from old cancelled tasks or a new head inserted while awaiting the network. | OfflineOutbox.scheduleReplay, cancelReplay |
| 13 | Offline state pauses replay without consuming another attempt; reconnection uses the existing replay hooks. | OfflineOutbox.scheduleReplay |
| 14 | Queue ownership is persisted and verified before/after sending. Unknown legacy and foreign-owner actions are retained, never reassigned; new unverified sends fail with draft recovery. | OutboxOperation.ownerID; OfflineOutbox enqueue/replay/retry |
| 15 | Queue writes are atomic/protected and must succeed before the in-memory queue or optimistic chat message changes. Persistence failure is surfaced, not reported as successful sending. | OfflineOutbox.commit; SocialStore.send |
| 16 | Corrupt/unreadable queue files remain untouched. New queueing is blocked until a successful read; recovery can retry storage without exposing message/account contents. | OfflineOutbox.load, statusMessage, canRetry |
| 17 | Queued activity rechecks current sharing choices before delivery. Revoked activity/details become a retained privacy hold, not a delayed privacy leak. | SeshReliabilityPolicy.mayReplayActivity; OfflineOutbox replay |
| 18 | Concurrent authentication refresh requests share one task; delayed Apple credential callbacks cannot replace a newer explicit sign-in or signed-out state. | Networking/SeshAuth.swift: refresh/expected-generation guards |
| 19 | Verified owner metadata survives relaunch in an additive, token-matched Keychain companion. Original raw tokens remain readable by earlier clients; sign-out cancels refresh/replay and clears remembered credentials. | SeshAuth keychain/auth lifecycle |
| 20 | Image memory/in-flight keys include bounded requested pixel dimensions, so a thumbnail is not reused as a blurry large image. | Core/ImagePipeline.swift |
| 21 | Image downloads stream with actual HTTP/MIME/URL/byte validation and a 16 MB cap before decode; disk reads also check size. | ImagePipeline.fetch |
| 22 | Shared image waiters and generation-safe cache clearing cancel irrelevant work without poisoning failure memory or repopulating cleared caches. | ImagePipeline flights/cancelWaiter/clear |
| 23 | Image failure memory, decoded cache and original-byte disk cache have explicit count/size bounds and expiry/pruning. | ImagePipeline pruneFailures/pruneDisk |
| 24 | Realtime socket generations prevent an old disconnect/receive-loop cleanup from clearing a newer connection or heartbeat. | Networking/SeshRealtime.swift |
| 25 | Socket frames are bounded, malformed/unknown messages ignored, change bursts coalesced, and heartbeat/reconnect waits cancel safely. | SeshRealtimeFramePolicy, scheduleChange, runLoop |

Items 20-25 have additional evidence in [SESH_MEDIA_REALTIME_6_2026_09_05.md](SESH_MEDIA_REALTIME_6_2026_09_05.md).
Paths in the table are relative to the app's `The SESH.` folder.

## Verification

- 72 native policy/actual-outbox checks pass. Production Outbox and SeshReliabilityPolicy are
  compiled unchanged against transport/account test doubles and isolated temporary fixture files.
  Checks cover idempotency, overflow, corruption, failed writes, owner isolation, legacy retention,
  cancelled completion, max-attempt overflow, privacy revocation and preserved retry deadlines.
- 19 additional native media/frame policy checks pass.
- The previous destructive singleton-queue test now uses an isolated fixture and verifies
  rejection without oldest-record loss. No real queue/account data was inspected or modified.
- Final generic physical-iOS app/widget build: 72, passed. Shared source compilation covers
  the real API, Keychain, UIKit image and realtime implementations.
- App test sources exist in SeshTests, but the current project does not configure that test target.
  Their syntax was checked; they are not claimed compiled/executed as app tests. Native runners are
  the actually-executed regression evidence.
- No simulator, remote service mutation, account action, push, upload or deployment occurred.

Native reproduction:

```sh
xcrun swiftc -parse-as-library 'The SESH./Core/SeshReliabilityPolicy.swift' 'The SESH./Networking/OfflineOutbox.swift' scripts/SeshReliabilityChecks.swift -o /tmp/sesh-reliability-checks
/tmp/sesh-reliability-checks
```

## Ownership, rollout and limitations

Owner: The Sesh client. Producers: existing verified Sesh auth/API responses, local social actions,
HTTP images and Worker WebSocket messages. Consumers: SocialStore, ConnectivityBanner/chat, shared
image views and the current auth layer. Private journal persistence does not depend on these services.
No Worker/site/Spotify contract or provider deployment is needed. Ship client changes together after
physical-device acceptance; new queue fields are optional/additive and dates/body/id remain compatible.

Old outbox files without verified owner metadata are deliberately retained but not automatically
submitted as the current account. Permanent-invalid/unknown-owner items require operator review;
the app does not offer unsafe cross-account adoption or automatic deletion. Eligible current-account
retry preserves server deadlines. A previous client can read the formats but lacks these privacy/hold
protections: do not downgrade with pending held work without reviewing that queue first.

Physical-device acceptance remains: two-account switch/sign-out during retry/Apple refresh,
offline-to-online chat, real disk-full/locked storage, queued privacy changes, streaming cache clear,
memory pressure, interrupted network, rapid websocket reconnect and event bursts. Native fixtures
and compilation do not prove live provider behavior, Keychain failure recovery or end-to-end UI.
Existing project deprecation/type-check warnings outside this batch remain.
