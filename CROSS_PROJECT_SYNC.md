# Cross-project sync

Also apply the ten additive cross-project safeguards in `PROJECT_GUIDE_ADDITIONS.md`; existing ownership and compatibility rules remain authoritative.

- `UnifiedWorker`: auth, social graph, rooms/WebSockets, lounge, APNs, Spotify, QA, and legacy shim.
- `site-repo`: public SESH pages, policies, age/safety language, support, and links.

Change client and Worker contracts together while keeping released payloads additive. WebSocket and auth changes require legacy-shim compatibility. Update site-repo for public policy or feature claims.

Sesh QA is available only during a ten-minute `Joo` passcode window. Unlocked iOS/iPadOS devices merge app-scoped tickets from every Sesh device through `POST /_unified/qa/tickets/sync` before retrying local writes. Mac apps do not expose in-app QA.
