# Unified AI, build, and cross-project instructions

This is the single authoritative instruction contract for Codex, Claude, and any other AI or build agent in this repository. Read `README_FIRST.md` first, then read only the sections below that match the current project and task. Legacy instruction filenames link here; do not duplicate rules into them.

## Task routing and updates

1. Identify the current repository and feature boundary before reading or editing code.
2. For UI work, read Product and UI rules; for data/API work, also read Cross-project ownership; for QA tickets, also read QA; for build/release work, also read Validation and publishing.
3. Inspect repository status and preserve unrelated changes. Search for existing implementations and tests before adding another path.
4. Load secrets only from ignored machine-local configuration or Keychain. Never copy values into source, prompts, logs, screenshots, fixtures, or documentation.
5. Default every metered AI request to the lowest-credit supported model and prefer on-device AI when it can satisfy the task. Preserve explicit user/operator model overrides; do not silently promote a default request to a costlier model.
6. When behavior, setup, compatibility, ownership, or validation changes, update the relevant section here and the concise project facts in `README_FIRST.md` in the same verified batch.
7. Shared changes must name an owner, producers, consumers, rollout order, fallback, migration/repair behavior, and verification matrix before publication.
8. Read narrowly to minimize tokens, but never skip a section selected by these routing rules.

## Project and UI rules



Every page, sheet, popover, and cover must fill its presentation with The SESH. theme, never a stock white host background. Layouts and controls must adapt to available width, device class, orientation, multitasking, safe areas, and Dynamic Type. Prefer flexible frames and adaptive composition; fixed dimensions are only for intentional artwork, QR, session-ring, or media geometry. Never constrain scrolling in a way that clips smaller screens or accessibility text, and avoid forced scrolling when content fits.

App-level headers and root tab bars have one shared implementation and one geometry source. Feature pages must not locally override brand placement, chrome height, safe-area spacing, icon slots, labels, or selected-tab geometry.

Use shared adaptive controls and JournalInputPolicy for complete locale-aware numeric parsing,
stable search/sort and draft baselines. Do not silently strip invalid pasted amount characters,
discard unfinished form fields or resurrect a record removed while an editor was open.
Keep chat composer text until SocialStore.send confirms durable queueing.

## Cross-project ownership and synchronization


- `UnifiedWorker`: auth, social graph, rooms/WebSockets, lounge, APNs, Spotify, QA, and legacy shim.
- `site-repo`: public SESH pages, policies, age/safety language, support, and links.

Change client and Worker contracts together while keeping released payloads additive. WebSocket and auth changes require legacy-shim compatibility. Update site-repo for public policy or feature claims.

Sesh QA is available only during a ten-minute `Joo` passcode window. Unlocked iOS/iPadOS devices merge app-scoped tickets from every Sesh device through `POST /_unified/qa/tickets/sync` before retrying local writes. Mac apps do not expose in-app QA.

OfflineOutbox owns durable optional social writes, not private journal saves. Never drop queued
actions at capacity/retry limits, replay unknown/foreign owners, or publish previously queued
activity after sharing is revoked. Preserve corrupt files; surface recovery without payload leaks.
Persist before optimistic success and remove by acknowledged identity only for the current replay
generation. Explicit Retry cannot shorten server cooldowns. Auth/GET retries retain the original
account generation across every await; stale refresh cannot replace newer sign-in or sign-out.
The original Keychain token remains raw; owner metadata is an additive token-matched companion.
ImagePipeline owns bounded size-specific decoded caching, streamed image limits and cache-clear
cancellation. Realtime frame limits and generation-guarded cleanup preserve polling fallback.
See docs/SESH_50_IMPROVEMENTS_2026_09_05.md for evidence, compatibility and device acceptance.

## Shared safety, validation, and publishing contract


### Project intake

1. Begin with the named entry point and expand scope only when evidence requires it.
2. State the feature boundary before editing so adjacent shipped behavior is preserved.
3. Identify the authoritative local, server, and generated data sources before changing models.
4. Keep credentials, signing material, user data, and machine-local configuration outside commits.
5. Treat released schemas, URLs, deep links, persistence formats, and extension contracts as compatibility surfaces.
6. Preserve offline/local-first behavior and provide a recoverable failure path for optional services.
7. Apply the complete product theme, adaptive layout, Dynamic Type, accessibility, and device-size contract to UI work.
8. Prefer migrations and retroactive repair over destructive replacement of existing records.
9. Run the narrowest meaningful validation first, then every affected target or consumer.
10. Finish only when behavior, setup, verification, documentation, and cross-project impact agree.

### Implementation and verification

1. Inspect repository status first and preserve unrelated user or agent work.
2. Make the smallest coherent batch that resolves the root cause without silently dropping features.
3. Search for existing abstractions, tests, and generated sources before adding parallel implementations.
4. Never expose secrets in code, logs, screenshots, fixtures, commits, or implementation briefs.
5. Keep public and persisted changes additive unless an explicit, tested migration removes the old path.
6. Update all affected app, widget, extension, Worker, site, and tooling consumers in the same coordinated task.
7. Test empty, loading, failure, offline, cancellation, retry, duplicate, and accessibility states when relevant.
8. Do not publish, deploy, migrate production data, or mark QA resolved after failed validation.
9. Record material decisions and new invariants in the existing short guides without duplicating large documentation.
10. Hand off with changed files, validation evidence, deferred risks, and any required operator action.

### Cross-project delivery

1. Name one owning repository for every shared schema, route, asset, or generated artifact.
2. List every producer and consumer before modifying a shared contract.
3. Preserve older clients with additive fields, tolerant decoding, stable URLs, and routing shims where required.
4. Define rollout order so providers remain compatible before consumers adopt new behavior.
5. Make migrations idempotent, resumable, observable, and safe to retry after interruption.
6. Keep secrets server-side or machine-local and synchronize only names, requirements, and validation—not values.
7. Propagate fixes retroactively to stored records when the invariant applies to old and new data.
8. Validate a matrix covering the owner, direct consumers, extensions/widgets, public content, and fallback paths.
9. Update README-first, AI instructions, cross-project sync, and public documentation in the same verified batch.
10. Retain a rollback or compatibility path until deployed clients and persisted data confirm the new contract.


## Automatic QA build numbering

Stocked owns `scripts/qa_build_number.py`; identical copies ship in all five QA-enabled Xcode repos.
Shared-scheme pre-actions reserve one project-wide integer, with a local locked high-water counter
and a DerivedData-scoped reservation. Per-target post-Info.plist/pre-signing phases stamp the actual
app, extension and test bundle. The generated plist is an input, not a declared output, to avoid an Xcode dependency-graph cycle.
User-script sandboxing is disabled only for this repo-owned local phase. App sandboxing/signing entitlements are unchanged. Scripts do not use the network or edit public
versions. Preserve `MARKETING_VERSION` byte-for-byte and avoid duplicate bumps in deployment scripts.
Validate built metadata and embedded bundles, not just project settings. Rollout is local project plus
script/scheme together; missing reservations fail, failed builds may leave gaps, and existing app/QA
schemas are unchanged. Tests are native fixture checks plus approved device-target builds; simulator
builds/tests require asking the user first. See `scripts/QA_BUILD_NUMBER.md`.
