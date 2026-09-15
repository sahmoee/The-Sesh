# Read me first

The SESH. is a privacy-minded iOS/iPadOS 26 cannabis journal and optional social app. Private sessions and journal data remain local-authoritative; network, community, push, and music failures must not block saving. Do not add commerce or medical claims.

The September 5 fifty-improvement pass is recorded in docs/SESH_50_IMPROVEMENTS_2026_09_05.md.
The September 14 pass adds ten private Journal Studio features and twenty polish fixes;
see docs/SESH_30_IMPROVEMENTS_2026_09_14.md. Open Track → Studio or Sesh Lab → Journal Studio.
Date/method views, notebooks, pins, reflections/follow-ups, comparisons, duplicate review, and
filtered CSV export use existing logs. Organization/reflections are protected device-local
metadata, not iCloud/social data or part of the existing full-journal backup. Follow-ups are
in-app dates, not notifications. Native Studio checks (41), existing journal checks (65), and
a generic iOS app/widget build passed; physical-device visuals remain unverified.
The separate September 14 code/polish pass adds 20 code fixes and 10 polish changes to
custom strains and personal goals; see docs/CODE_POLISH_PASS_2_2026_09_14.md. Catalog search
uses cached normalized indexes. Custom strains/goals migrate legacy arrays into protected
atomic local files before mirroring; corrupt or oversized originals pause edits and remain
preserved. Goals use real calendar weeks and validated limits. Catalog/goal native checks (76),
Studio (41), journal (65), and generic app/widget build 78 passed; device checks remain pending.
Journal forms protect drafts, validate complete localized numbers and preserve current metadata
when editing. Shared adaptive controls, real journal sorting, recoverable filtering and outbox
feedback use the current theme. Offline social writes must persist before optimistic success:
deduplicate stable keys, reject overflow without dropping old work, hold failed/legacy/unowned
actions, recheck account and sharing preferences before replay, and honor server cooldowns.
Social sends need a verified account once; failed queueing retains the chat draft.
Auth refresh is single-flight and generation-guarded. Raw Keychain tokens remain compatible;
an additive token-matched owner companion supports safe queue attribution. Media caches are
pixel-size-aware, bounded and cancellation-safe; realtime reconnects cannot clean up newer sockets.

The native watchOS 26 companion is implemented in `SeshWatch/`, `WatchShared/` and
`The SESH./Watch/`; see docs/WATCHOS_APP_2026_09_14.md. It supports private logging,
timers, thoughts, stash/deductions, goals, favorites/pins, and full iPhone history/catalog
pagination. The paired iPhone remains authoritative; protected drafts and a 100-command
UUID outbox survive offline restart. Durable receipts prevent duplicate log/deduction replay.
Foreign journal epochs require a correlated current handshake before clearing the Watch copy.
No social publication, new Worker routes or secrets are involved. Native wire/storage checks
(82) and actual production-model SwiftData checks (11) pass; generic watchOS+iOS companion
builds pass with matching app/Watch/widget version 59 (84). Eight stable Watch QA journeys remain untested on paired hardware. Build using
shared `SeshWatch` or `The SESH.` schemes, preserving automatic matching bundle numbers.

Shared services use `https://api.sowensstudios.com/sesh`; secrets belong server-side or in Keychain. Start in the feature folder named by the task and verify the main app plus widget/network impact.


Build numbers are automatic through shared Xcode schemes; `MARKETING_VERSION` remains manual.
The repo-owned `scripts/qa_build_number.py` reserves a locked project-wide number and stamps every
built app/extension/test plist before signing. It is vendored from Stocked; see
`scripts/QA_BUILD_NUMBER.md`. Use a shared scheme, not a direct `-target` build. Simulator builds/tests
currently require the user's approval; this setup does not authorize uploads.
