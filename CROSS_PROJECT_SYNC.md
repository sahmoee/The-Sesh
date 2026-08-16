# Cross-project sync

- `UnifiedWorker`: auth, social graph, rooms/WebSockets, lounge, APNs, Spotify, QA, and legacy shim.
- `site-repo`: public SESH pages, policies, age/safety language, support, and links.

Change client and Worker contracts together while keeping released payloads additive. WebSocket and auth changes require legacy-shim compatibility. Update site-repo for public policy or feature claims.
