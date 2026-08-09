# The Lounge — SESH-RL-001-R2: Phase 4 + Compose (completes the spec)

August 2, 2026. This batch finishes the revised Lounge specification. Phases 1–3 (home entry, quick actions, organized-chaos feed, expanded post views) were already built; this adds everything that remained.

## §13.1 Audit output (what existed vs. what was missing)

**Already existed and reused:** LoungeModels / deterministic LoungeLayoutEngine (FNV-1a seeded, band-based, §6 verified by property tests), LoungeFeedStore (cursor paging, stable ordering, optimistic reactions/votes, hide/report), all §8 post cards, LoungeFeedView (lamp, centered serif title, For You/Following/Live Now, filter rail), LoungePostDetailView, EnterLoungeCard, Compare Strains flow (§4.2 — CompareStrainsView already complete), Quick Actions already exactly Add Purchase / Log Session / Compare Strain (§4.1), LoungeDO worker (feed, canView visibility, idempotent create, sanitized polls/media), RoomDO (per-room chat, rate limits, WebSockets), auth, offline outbox, PrivacySettings field-level sharing, report/block flows.

**Missing (now built):**

1. **Compose flow** — there was no way to post.
   - `LoungeComposeView` (new): 8 post kinds (High Thought, Rant, Photo, Munchies, Poll, Check-In, Review, Music), char-count guidance matched to the §6.3 template rules (≤180 floats as a bubble, >280 goes full-width), 2–6 choice poll builder, Apple Music/Spotify track attach via the existing search, review with strain type-ahead + rating, sesh-context chips defaulted from PrivacySettings (§12 field-level sharing) and prefilled from the live/latest sesh, Everyone/Friends visibility, discard guard, full VoiceOver support incl. author-supplied photo alt text.
   - Photos are downscaled to 1280px JPEG on device (strips EXIF/GPS per §12) and uploaded to the new worker media endpoint.
   - `LoungeFeedStore.createPost/insertLocal`: upload → create → prepend at top of For You + Following without reshuffling any visible placement (§11 — the new post is planned as its own leading band; existing bands untouched). Just-composed posts are protected against racing refreshes.
2. **Media hosting** (worker) — `POST /api/lounge/media` (auth, 2 MB cap, 20/10 min rate limit, KV-backed, 180-day TTL) and public capability-URL serving `GET /api/lounge/media/:id` with immutable caching.
3. **Phase 4 — Live integration.**
   - `LoungeLiveRoomView` (new): full-screen "shared active space" per §9 — not livestreaming. Message feed on the existing room infrastructure (merging poll every 5s, cancels on background), quick reactions (🔥 😂 💨 🎶), live presence from the new `GET /api/rooms/:id/presence`, LIVE/ENDED pill, vibe tags, participant avatars.
   - Host controls: End Session (confirmed) → `POST /api/lounge/live/end` (author-only server-side; host identified by the verified session uid).
   - Graceful ended state (§9): "This sesh has ended" + "Still burning" list of other live rooms with in-place Join, + Back to the Lounge. Live posts older than 24h are served as ended (staleness cap).
   - Join is real everywhere: feed cards and the detail sheet share one join path (detail dismisses first, then presents the room — no dropped presentation).
   - Live Now tab now renders a uniform single-column list of consistent full-width live cards (§9), while For You/Following keep the organized-chaos bands. Server auto-provisions `roomID = "lounge_<postID>"` for live posts.
4. **Functional music player** (§8 Table 3) — `LoungePreviewPlayer` (new): one shared AVPlayer, real progress, one preview at a time, `.ambient` session (respects the silent switch), stops on card disappear/backgrounding/leaving the Lounge; "Open in Music" fallback when no preview URL. Wired into feed cards and the detail view.
5. **Block reconciliation** (known gap from Phase 1–3 notes): social block/unblock now fans out to LoungeDO so the two block lists can't drift.
6. **Fixes discovered during adversarial verification:** `/create` responses are now decorated (they didn't decode client-side), the API date decoder tolerates fractional-second ISO-8601 (worker `toISOString()` dates), photo alt text is persisted end-to-end and read by VoiceOver, and compose/reset race protection as above.

## Deploy

- **Xcode:** three new files should be picked up by the synchronized group: `The SESH./Lounge/LoungeComposeView.swift`, `The SESH./Lounge/LoungeLiveRoomView.swift`, `The SESH./Lounge/LoungePreviewPlayer.swift`. Build.
- **Worker:** `cd _worker/sesh-worker && wrangler deploy`. No new secrets; media uses the existing KV binding.
- Verified: per-file Swift syntax checks clean, `tsc --noEmit` clean, full-diff adversarial review (7 findings, all fixed before packaging).

## Deliberately not in this batch

Video upload/playback (media pipeline is photo-first; the card/template support exists), full livestreaming (§9 explicitly defers it), server-side ranking refinement and analytics (Phase 5 tail), SharePlay/collaborative queue.
