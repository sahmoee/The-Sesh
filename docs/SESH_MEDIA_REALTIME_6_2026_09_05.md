# Sesh media and realtime: six reliability improvements

Implemented September 5, 2026. These six items belong to the parent task's 25 core improvements and are **not** an additional count beyond the requested 50 Sesh improvements.

| # | Implemented improvement | Production evidence |
| --- | --- | --- |
| 1 | Image memory and in-flight identities include the normalized requested pixel size (64–2048 pixels, safe defaults for invalid values), preventing a cached thumbnail from being reused as a blurry hero. Original bytes remain shared on disk. | `The SESH./Core/ImagePipeline.swift`: `image`, `NSCache<NSString, UIImage>`, `inFlight`; root-owned `SeshReliabilityPolicy.imagePixels/imageKey` |
| 2 | Remote image fetching allows only HTTP(S) hosts, checks final URL/status/MIME/advertised size, streams at most 16 MB, cancels the actual data task on rejection/exit, rejects empty or undecodable content, and downsamples away from the UI actor. Existing disk data is size-checked before reading. | `ImagePipeline.swift`: `acceptsURL`, `fetch`, `downsample` |
| 3 | Clearing caches invalidates the generation and cancels all in-flight producers before deleting cache contents. Waiter IDs preserve shared work while a different caller still needs it; canceling the last waiter stops the producer. Canceled results do not create failure cooldowns, and stale completion cannot repopulate cleared caches or remove a newer flight. | `ImagePipeline.swift`: `Flight`, `cancelWaiter`, `generation`, `clear`, result publication |
| 4 | Failure cooldowns are expired/pruned and capped at 256 entries. Decoded cache cost/count is bounded, original-byte disk cache is pruned oldest-first to 128 MB and 512 files, and the redundant URLSession disk cache is disabled. | `ImagePipeline.swift`: `pruneFailures`, `pruneDisk`, URLSession configuration |
| 5 | WebSocket receive-loop and deferred connection cleanup are guarded by connection generation and socket identity. Old disconnect cleanup cannot cancel a newly connected heartbeat, clear the new task, or publish a stale connection state. | `The SESH./Networking/SeshRealtime.swift`: `connect`, `disconnect`, `runLoop(generation:)` |
| 6 | WebSockets cap frames at 64 KB before JSON work, ignore malformed/unknown message types, coalesce change bursts into at most one callback per 250 ms, and make auth waits/reconnect/heartbeat sleeps cancellation-safe. Pending change callbacks are canceled on disconnect. | `SeshRealtime.swift`: `SeshRealtimeFramePolicy`, `maximumMessageSize`, `scheduleChange`, `pause`, `startHeartbeat` |

## Verification

- **19 native policy checks passed** using the exact production Foundation declarations, not copied policy implementations. Checks cover invalid/bounded pixel dimensions, size-specific identities, image status/MIME/byte bounds, and valid/unknown/malformed/empty/oversized realtime frames.
- Added three Swift Testing cases in `SeshTests/SeshMediaPolicyTests.swift` covering the image and frame contracts. Test-target compilation/execution is owned by the parent task.
- Swift parser validation passed for both changed production files and the new test file. `git diff --check` passed.
- No simulator, device build, backend request, deployment, or commit was run by this subtask.

Reproduce the native checks from the repository root:

```sh
{ sed -n '1,$p' 'The SESH./Core/SeshReliabilityPolicy.swift'; awk '/^nonisolated enum SeshRealtimeFramePolicy/{copy=1} copy{print} copy && /^}/{exit}' 'The SESH./Networking/SeshRealtime.swift'; sed -n '1,$p' scripts/SeshMediaPolicyChecks.swift; } | xcrun swift -
```

Concurrency/device acceptance still required: same URL requested concurrently at thumbnail and hero sizes; one waiter canceled while another remains; clear while a streamed image is pending; disk-budget overflow; rapid sign-out/reconnect; lost connection during heartbeat; and bursts of social change frames. Pure policy tests and parsing do not prove these live interaction scenarios.

## Compatibility and ownership

Owner: Sesh client. Producers: configured HTTP image sources and existing UnifiedWorker/legacy WebSocket messages. Consumers: shared image users and SocialStore callbacks. Public method signatures and the Worker message schema remain unchanged; no Worker deployment is required. The original disk-cache filename scheme is retained, so existing image bytes remain reusable and oversized/corrupt entries recover through the normal network path. No journal, photo original, private session, credentials, or social records are deleted. Client rollout follows device QA, with the previous client build as rollback.

The optional social channel still falls back to SocialStore polling. Image failure still returns a placeholder-compatible nil without blocking journal/session saves. Missing Content-Type is tolerated for compatibility only when the downloaded bytes successfully decode as an image.
