# Changelog

Every push should add an entry here so GitHub carries the build/change history.
Newest at the top. Keep it plain ASCII (see .gitmessage.txt for the commit rules).

## [Unreleased]
- Build 65 follow-up separates Home controls, lamp, and greeting into explicit layout rows so the Ready pill cannot overlap the hanging light at any supported width or Dynamic Type size.
- Build 65 expands the normalized strain reference from 1,453 to 9,598 entries, adds a repeatable licensed-data updater, relevance search, informative-profile filtering, transparent missing-data/source labels, trait-based similar strains, and a home lamp layout that no longer covers controls or content.
- Build 64 fixes the foreground push delegate compilation regression and adds async permission handling, preference-aware APNs registration, persisted and deduplicated device tokens, token-rotation cleanup, real server unregistration when notifications are disabled, notification-center cleanup, structured realtime messages, and heartbeat failure recovery.
- Build 63 fixes incorrect online and active-Sesh timing with foreground-only presence leases, explicit background release, independent Sesh expiry, fresh-only notifications, duplicate push prevention, stale Cypher/live cleanup, and clearer online/offline UI.
- Expanded documentation across sessions, journal, strains, stash, music, social/community, persistence, offline behavior, integrations, testing, release operations, troubleshooting, privacy, and safety.
- Added the Unified QA ticket queue with automatic screenshots, device/build context, offline persistence, upload retry, editable statuses, required fix resolutions, tester verification, and history-preserving refiles.
- Added professional setup, build, security, contribution, and issue-reporting documentation.
