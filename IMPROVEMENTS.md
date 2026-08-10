# The SESH — 70 Improvements

July 29, 2026 · 61 files changed across the app, widget, worker, and tests.
Every Swift file passed syntax verification; the worker passes `tsc --noEmit` with zero errors; all changes were adversarially re-reviewed by a second pass and the five issues it found were fixed before packaging.

**One new file must be added to the Xcode app target: `The SESH./Persistence/StorageHealthBanner.swift`** (the synchronized group should pick it up automatically). Everything else is edits to existing files. Redeploy the worker (`wrangler deploy`) to pick up the backend fixes.

---

## Correctness — things that were broken (1–12)

1. **Home "Roll Up" / "Smoking" tiles now start the flow you picked.** The chosen activity was captured and then silently dropped — every tile opened the generic search screen. `RootView` now presents `StartSeshView(initialActivity:)`. *(CoreUI/RootView.swift)*
2. **The widget's "End Sesh" button now actually ends the sesh.** It set a flag nothing read and opened a *Start a Session* screen. Now routes to the end-immediately path that already existed but was dead code. *(RootView.swift, Session/StartSeshView.swift)*
3. **Every sesh ended from the active screen was silently rated 8/10**, skewing Smart Picks recommendations. The summary now has a real rating slider and saves your answer. *(Session/SeshFlow.swift)*
4. **Journal empty state lied.** "Nothing matches" showed even when thoughts matched your search, and the summary bar always counted "sessions" on the Thoughts tab. Both now reflect what's actually on screen. *(Journal/JournalView.swift)*
5. **Insights showed "Day Streak" twice.** The duplicate stat box is now Avg Duration. *(Insights/StatsViews.swift)*
6. **The spend chart's y-axis was hardcoded at $60/40/20/0** while bars scaled to your real spending — every bar was mislabeled past $60/week. Labels now derive from the actual max. *(StatsViews.swift)*
7. **Cost-per-sesh divided by the wrong denominator** (all sessions, not priced ones), and the stash forecast divided 3 days of history by 30 and hardcoded grams. Fixed both; the forecast now uses your real history window and your purchases' actual unit. *(Features/CostAnalyticsView.swift, StashForecastView.swift)*
8. **Strain placeholder art reshuffled on every app launch** — `hashValue` is per-process seeded (the same bug fixed once before in StrainImageStore). Journal and photo placeholders now use the stable seed. *(Journal/JournalView.swift, PhotoSupport.swift)*
9. **Opening the Listen tab silently created four empty "… Mix" playlists** by mutating the store during view rendering. Playlists are now created (or found) only when you tap a vibe. *(Music/ListenView.swift)*
10. **The music transport icon never updated** — playback state wasn't observable, and pausing in Apple Music went undetected. Both fixed via the playback-state notification. *(Music/ScrobbleStore.swift)*
11. **Your own chat message could vanish after sending** if the server page raced the offline outbox — the optimistic copy was wholesale-replaced. Messages now merge by id. *(Social/SocialStore.swift)*
12. **Re-picking the same photo did nothing** (picker item never reset) and photo-load failures were silently swallowed. Both fixed, with a visible error on failure. *(Journal/PhotoSupport.swift)*

## Security & backend hardening (13–26)

13. **Critical: every user's handle, live activity, and now-playing track leaked to every other user.** The snapshot marked all users as friends without ever reading the friends list. Friends, presence, and the feed are now filtered by real friendships (admin export retains the full view, key-guarded). *(worker/src/social.ts)*
14. **Sign in with Apple verification failed open** if `APPLE_BUNDLE_ID` was ever unset — a token minted for *any* app would create a session. Now fails closed. *(worker/src/auth.ts)*
15. **Session tokens were accepted via `?token=` on every route**, leaking bearer tokens into access logs. Now only WebSocket upgrade paths may use it. *(auth.ts)*
16. **Anyone could forge another user's online presence** — the WS heartbeat trusted a client-supplied uid. Sockets are now tagged with the authenticated uid at accept time. *(social.ts)*
17. **Friend codes could be hijacked** by registering someone else's code, intercepting their friend-adds. Registration now rejects codes mapped to a different account. *(social.ts)*
18. **Junk visibility values made "private" posts world-readable** — an unvalidated cast fell through every check. Whitelist enforced, defaulting to public. *(worker/src/lounge.ts)*
19. **React, vote, comment, and hide skipped visibility checks entirely** — anyone with a UUID could comment on a private post. All four now run the same guard as the feed. *(lounge.ts)*
20. **Poll results could be pre-faked and choices were unbounded.** The server now caps choices at 6, clamps labels, and zeroes all vote counts on create. *(lounge.ts)*
21. **Offline replays created duplicate Lounge posts** — `/create` ignored the idempotency key the router forwarded. Honored now. *(lounge.ts)*
22. **A failed write permanently swallowed its own retry** — idempotency keys were committed *before* handlers ran. Keys are now recorded only after success. *(social.ts)*
23. **A client-controlled playlist ID was interpolated raw into the Spotify API path** (path traversal into other endpoints). Now validated against Spotify's ID format and encoded; track payloads capped at 1,000. *(worker/src/spotify.ts, index.ts)*
24. **A negative `?limit=` crashed the rooms API with a 500.** Clamped to 1…200. *(worker/src/rooms.ts)*
25. **An evicted feed cursor silently restarted infinite duplicate scroll.** Timestamp fallback added; the feed now honestly ends. *(lounge.ts)*
26. **Comment counts diverged from reality past the 200-comment cap**, and three endpoints returned bare-text errors while everything else returned JSON. Both unified. *(lounge.ts, social.ts, rooms.ts)*

## Data safety (27–33)

27. **Silent total data loss is now visible.** When SwiftData fails to open and runs memory-only, everything *looked* normal and vanished on relaunch — the flag existed but nothing read it. A storage-health banner now warns; the connectivity banner (built but never mounted anywhere) is now mounted too. *(Persistence/StorageHealthBanner.swift — new, RootView.swift)*
28. **Ending a sesh now asks first.** It was instant and irreversible from the active screen, its menu, and the Home card. *(Session/SessionActiveView.swift, ActiveSeshCard.swift)*
29. **The summary's back chevron discarded your entire finished sesh** with no warning — and by then the live state was already cleared, so it was unrecoverable. Now confirms. *(SeshFlow.swift)*
30. **Backing out of Save/Log threw away your rating, effects, notes, and photo silently.** Both screens now detect edits and confirm discard. *(SaveSeshView.swift, LogSeshView.swift)*
31. **"Clear" wiped the whole notification inbox in one tap.** Now confirms. *(CoreUI/NotificationViews.swift)*
32. **Deleting a journal category un-tagged every entry using it on a single 14pt tap** — now confirms; "End Break" (which erases a multi-day T-break streak) also confirms and regained its destructive styling. *(JournalView.swift, SeshExtrasViews.swift)*
33. **Journal export could hand you a share sheet for a file that failed to write**, and left your full plaintext journal in temp storage forever. Write is now checked; the temp file is cleaned up after sharing. *(Profile/ProfileView.swift)*

## UX & polish (34–48)

34. **Fake data removed:** every user shipped with hardcoded "recent searches" (After Hours, Nights, Redbone). Recents are now real, deduped, capped, with a proper empty state. *(SeshFlow.swift)*
35. **The Follow button was fake** — it fired a haptic and flipped its label with no backend. Removed rather than shipping a lie. *(Lounge/LoungePostDetailView.swift)*
36. **The live-post "Join" dead-end loop is gone** — feed Join opened the detail, detail Join did nothing. Both now route to one path with honest "coming soon" messaging until rooms ship. *(LoungePostDetailView.swift, LoungeFeedView.swift)*
37. **Failures no longer masquerade as success:** report submissions, poll votes, and comment posts all showed nothing (or dismissed as if fine) on failure. All three now surface errors, and vote state syncs from the server. *(LoungeFeedView.swift, LoungePostCards.swift, LoungePostDetailView.swift)*
38. **Double-tapping "Start Cypher" created two Cyphers.** In-flight guard added (and correctly reset when you leave the room). *(Social/CypherViews.swift)*
39. **The "Say something to the Cypher" prompt rendered above every message, always.** Now only when the room is empty. *(CypherViews.swift)*
40. **Empty states and pull-to-refresh** added to Chat rooms and Cyphers (with a "Host a Cypher" action); missing-playlist and no-search-results screens no longer render blank. *(ChatViews.swift, CypherViews.swift, Music/PlaylistViews.swift)*
41. **Search is debounced** — strain search filtered the entire catalog on every keystroke in render; track search had no as-you-type mode at all and raced itself. Both now debounce ~300ms with cancellation. *(SeshFlow.swift, PlaylistViews.swift)*
42. **Dead controls resolved:** "See all" strains was a styled label that did nothing — now a working button; the Invite and Add Product session tools routed to nowhere — hidden until they exist; Create Playlist no longer silently falls back on an empty name. *(SeshFlow.swift, QuickActions.swift, PlaylistViews.swift)*
43. **The budget editor silently zeroed your budget on bad input** and hardcoded a "$" next to locale-aware totals. Validated with a toast, locale currency symbol derived. *(SeshExtrasViews.swift)*
44. **Money and dates are now locale-aware everywhere:** eight `"$%.0f"`-style call sites routed through the cached currency formatter; date/time formatters switched to localized templates (24-hour clocks work now). *(Helpers.swift, JourneyRecordsViews.swift, JourneyView.swift, StashView.swift + others)*
45. **"now ago" is gone** — the relative-timestamp bug visible on fresh Lounge posts — and the three duplicate relative-time implementations are now one. *(Lounge/LoungeModels.swift + cards/detail)*
46. **Back-to-back toasts no longer cut each other short** (timer now restarts per message), and toasts are announced to VoiceOver. *(Helpers.swift)*
47. **Haptics polish:** Lounge card opens now give feedback, and generators are long-lived and prepared — the first haptic after launch no longer lags. *(LoungeFeedView.swift, Helpers.swift)*
48. **Community-prompt answers were silently discarded** ("submit" did nothing). They now save to High Thoughts, and the copy says so honestly. *(Stash/GoalsAndExtras.swift)*

## Accessibility (49–58)

49. **`Font.seshScaled` claimed Dynamic Type support and delivered none** — it returned a fixed size. It now actually scales with the user's text size. *(CoreUI/Accessibility.swift)*
50. **Dozens of controls collapsed into single, labeled VoiceOver elements:** Home tiles, session chooser rows, quick-action tiles, editor rows, milestone medallions, stash rows, and both widget layouts (which had zero accessibility). *(HomeView, SeshFlowViews, QuickActions, JourneyRecordsViews, StashView, SeshWidgetBundle)*
51. **Values exposed:** rating slider ("7 out of 10"), progress bars (percent), tolerance gauge — all were mute to VoiceOver. *(Components.swift, SeshExtrasViews.swift)*
52. **Selection exposed:** filter pills, underline tabs, theme cards, icon styles, and the mood scale now report `.isSelected`. *(Components.swift, AppearanceView.swift)*
53. **44pt minimum tap targets** applied across the Lounge (hearts, comments, overflow, play/pause, send), Journal (heart, clear, pencil, trash), Music back chevron, notification bell, and the session card's expand glyph — the helper existed with exactly one adopter. *(9 files)*
54. **Icon-only controls labeled:** notification bell (announces unread count), status pill (label + hint), retry button, close button (with "your sesh keeps running" hint), invisible spacer removed from the accessibility tree. *(NotificationViews, StatusPill, ConnectivityBanner, StartSeshView)*
55. **Two of the five mood faces were literally the same symbol.** All five are now distinct, labeled, and report selection. *(Components.swift)*
56. **Reduce Motion is honored:** remaining `withAnimation` calls routed through the motion-aware helper, and the roll-up confetti — which animated 80 shapes forever — now renders a static burst under Reduce Motion and stops after 3 seconds for everyone. *(SeshFlowViews.swift + 3 files)*
57. **Large-text fixes:** the friends list hard-coded 78pt rows inside a disabled-scroll List (clipped at accessibility sizes) — now intrinsic height with context-menu actions; add-friend results are announced; the unlabeled "who can join" picker is named. *(FriendViews.swift, CypherViews.swift)*
58. **The widget got safe URLs too** — three force-unwrapped `URL(string:)!`, a declared-but-unused icon fallback (missing assets rendered blank), and description copy that didn't match its buttons. All fixed. *(SeshWidget/SeshWidgetBundle.swift)*

## Performance (59–66)

59. **Timer hygiene:** the active-session screen created a new auto-connected timer on every view re-init and kept ticking under covers — replaced with TimelineView; the Home card's 1-second timeline wrapped the whole card (image loads, strain lookups re-ran every second) and now wraps only the clock text. *(SessionActiveView.swift, ActiveSeshCard.swift)*
60. **Task lifecycle:** unstructured timer/loader tasks that stacked on re-entry and outlived their views (elapsed ticker, roll timer, lounge tab switches) are now structured and auto-cancelling; ~10 `onAppear` work sites moved to `.task`. *(StartSeshView, LoungeFeedStore + others)*
61. **Heavy work out of the render loop:** badge building (~25 full passes over your journal per render), journey/personality builders, and music aggregations (grouping the full play history per row) are now computed once and refreshed on data change. *(InsightsScreens, JourneyRecordsViews, MusicMemoryViews)*
62. **The share-card was rasterized at 3× twice per render on the main thread** — once for the button, once for the preview. Now rendered once, cached, refreshed when the card actually changes. *(Features/RecapCardsView.swift)*
63. **FlowLayout measured every subview twice per layout pass** — now uses the Layout cache. *(Components.swift)*
64. **Per-row formatter allocations eliminated** (RelativeDateTimeFormatter in three list views, ISO8601 per API call, DateFormatter per summary render) — all now cached, matching the codebase's own documented convention. *(4 files)*
65. **Cache correctness:** the strain image LRU appended duplicate keys and evicted live entries; the photos folder ran filesystem checks on every single image access. Both fixed. *(StrainImageStore.swift, PhotoSupport.swift)*
66. **Radios off when idle:** Spotify polling now respects connectivity (no more blind 20-second hits while offline), and the social status card no longer re-renders at 1Hz when nothing is active. *(ScrobbleStore.swift, SocialViews.swift)*

## Code quality (67–70)

67. **Crash-class force unwraps removed:** five `URL(string:)!` in deep links (one interpolated an arbitrary friend code — any special character crashed the app), two `firstIndex(of:)!`, the mailto link, and three widget URLs. *(SeshFlowViews, StartSeshView, SafetyAndPrivacy, SeshWidgetBundle)*
68. **Dead code deleted:** CreamCard, footerTiles, `startAfterSave` + its dead branch, unused state vars, an unused observable dependency that re-rendered Home on every strain mutation, and a stale `import Combine`. *(Components, HomeView, RootView, LogSeshView, SessionActiveView)*
69. **Design-system consistency:** new Spacing tokens and Radius.xs/.bubble in the theme; magic corner radii routed through tokens; stringly-typed "Who's Joining?" is now a real enum; four duplicate duration formatters became one; theme colors froze at struct-init in Home (working only via a full-tree rebuild hack) — now live. *(Theme.swift + 6 files)*
70. **Tests added:** currency-formatter branching, offline-outbox overflow trim (505 → oldest 5 dropped), and the companion-line model logic — three suites covering previously untested pure logic. *(SeshTests/SeshCoreTests.swift)*

---

## Deploy notes

- **Xcode:** add `The SESH./Persistence/StorageHealthBanner.swift` to the app target if the synchronized group doesn't pick it up; build.
- **Worker:** deploy the separate UnifiedWorker repository (no new secrets, no migrations — all changes are code-level).
- Verification performed: per-file Swift syntax checks (all clean), `tsc --noEmit` (clean), full-diff adversarial review with 5 findings found and fixed (admin-export regression, camera-return data wipe in LogSeshView, over-tight track cap, stuck Start Cypher guard, stale recap cache).
