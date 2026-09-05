# Read me first

The SESH. is a privacy-minded iOS/iPadOS 26 cannabis journal and optional social app. Private sessions and journal data remain local-authoritative; network, community, push, and music failures must not block saving. Do not add commerce or medical claims.

The September 5 fifty-improvement pass is recorded in docs/SESH_50_IMPROVEMENTS_2026_09_05.md.
Journal forms protect drafts, validate complete localized numbers and preserve current metadata
when editing. Shared adaptive controls, real journal sorting, recoverable filtering and outbox
feedback use the current theme. Offline social writes must persist before optimistic success:
deduplicate stable keys, reject overflow without dropping old work, hold failed/legacy/unowned
actions, recheck account and sharing preferences before replay, and honor server cooldowns.
Social sends need a verified account once; failed queueing retains the chat draft.
Auth refresh is single-flight and generation-guarded. Raw Keychain tokens remain compatible;
an additive token-matched owner companion supports safe queue attribution. Media caches are
pixel-size-aware, bounded and cancellation-safe; realtime reconnects cannot clean up newer sockets.

Shared services use `https://api.sowensstudios.com/sesh`; secrets belong server-side or in Keychain. Start in the feature folder named by the task and verify the main app plus widget/network impact.


Build numbers are automatic through shared Xcode schemes; `MARKETING_VERSION` remains manual.
The repo-owned `scripts/qa_build_number.py` reserves a locked project-wide number and stamps every
built app/extension/test plist before signing. It is vendored from Stocked; see
`scripts/QA_BUILD_NUMBER.md`. Use a shared scheme, not a direct `-target` build. Simulator builds/tests
currently require the user's approval; this setup does not authorize uploads.
