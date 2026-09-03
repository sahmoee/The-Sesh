# Read me first

The SESH. is a privacy-minded iOS/iPadOS 26 cannabis journal and optional social app. Private sessions and journal data remain local-authoritative; network, community, push, and music failures must not block saving. Do not add commerce or medical claims.

Shared services use `https://api.sowensstudios.com/sesh`; secrets belong server-side or in Keychain. Start in the feature folder named by the task and verify the main app plus widget/network impact.


Build numbers are automatic through shared Xcode schemes; `MARKETING_VERSION` remains manual.
The repo-owned `scripts/qa_build_number.py` reserves a locked project-wide number and stamps every
built app/extension/test plist before signing. It is vendored from Stocked; see
`scripts/QA_BUILD_NUMBER.md`. Use a shared scheme, not a direct `-target` build. Simulator builds/tests
currently require the user's approval; this setup does not authorize uploads.
