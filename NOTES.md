# The SESH — chat identity + storage fixes (2026-08-03)

These files have already been written into `~/Documents/The SESH.` on this Mac.
This folder is a copy of the same edits (project-relative paths) plus
`changes.diff`, so the change set can be reviewed or re-applied elsewhere.

**The Worker changes need `wrangler deploy` to take effect.** The app changes
need a rebuild in Xcode. No new files were added to the Xcode project, so no
project file changes are required.

---

## 1. "Storage unavailable — data won't be saved after you close the app"

`The SESH./Persistence/Persistence.swift`

The app ships the iCloud entitlements (`CloudKit` + `CloudDocuments`, needed for
`CloudSync.swift`). SwiftData's `ModelConfiguration` defaults to
`cloudKitDatabase: .automatic`, which means "mirror this store to CloudKit if
the app is entitled to it" — and it was. CloudKit mirroring forbids
`@Attribute(.unique)`, and all three models use it (`SDJournalEntry.id`,
`SDThought.id`, `SDRecord.key`). So the on-disk `ModelContainer` threw on every
single launch, the initializer fell through its recovery chain to the
memory-only branch, and the banner was telling the exact truth: nothing was
being written to disk.

The fix is one parameter — `cloudKitDatabase: .none` on every container attempt.
Cross-device sync doesn't depend on this store; it goes through
`NSUbiquitousKeyValueStore` and the Worker, both untouched.

Two supporting changes:

- A new step in the recovery chain: before giving up and going memory-only, try
  a durable store at a secondary location (`SeshLocalStore.store` in Application
  Support). The original store file is never touched or deleted, so nothing is
  destroyed and a later build can still recover it. `isUsingFallbackLocation`
  and `lastFailure` are exposed for diagnostics.
- `The SESH./Persistence/Models.swift`: `migrateFromUserDefaultsIfNeeded()` no
  longer trusts the `migrated` flag on its own. While storage was broken the
  store looked empty every launch, so the flag was set without anything being
  migrated — meaning a journal that still exists in UserDefaults/iCloud would
  *not* come back once storage started working. It now re-runs whenever the
  store is empty and there is real legacy data. This is idempotent: every save
  mirrors the working set back into UserDefaults, so an intentionally emptied
  journal has nothing to resurrect.

## 2. Your messages showed as "You" on other devices

Root cause: `"You"` / `"@you"` was used as the empty-name fallback in four
places, and it got **persisted as the sender's identity**. A display name is
second-person only on the device that owns it — the moment it's stored on a
message it becomes the label everyone else reads.

The chain was: no profile name set → `SocialStore.configure` substituted `"You"`
→ that was sent at sign-in → the Worker put it in the session claims → `RoomDO`
stamped it onto every message → every other device rendered it verbatim.

Fixed at each link:

- `SocialStore.swift`: blank names now become a stable `Sesher 7K9F` (the same
  FNV-1a tag already used for friend codes), the placeholder identity is no
  longer `"You"/"@you"`, and the handle fallback is `@sesher`.
- `util.ts` (new): `displayName()`, `displayHandle()`, `shortTag()`,
  `isSelfLabel()` — shared helpers that never return a second-person label.
- `index.ts`: both auth endpoints run names through those helpers, so a session
  can no longer be minted with the name "You".
- `rooms.ts`: messages are stored with a real name, and **messages already
  stored as "You" are repaired on read** — the stored rows are left alone, so
  no migration is needed and old history stops showing "You" immediately after
  deploy.
- `social.ts` / `lounge.ts`: the same normalization on user records, posts and
  comments.
- `SocialModels.swift` / `ChatViews.swift`: `ChatMessage.authorLabel` is used
  for the name above someone else's bubble. A message that isn't yours is never
  labelled "You", even if it came from a stale local cache.

### New: `POST /api/profile`

The display name lives inside the session token, so setting or changing your
name after sign-in used to be invisible to everyone else for up to 24h (until
the token expired). The new endpoint re-mints a session for the *same verified
uid* — no re-authentication, no sign-in sheet — and the app swaps the token in
(`SeshAuth.adoptRefreshedSession`). `SocialStore` calls it on identity change,
debounced by 1.5s so typing a name doesn't mint a token per keystroke.

## 3. Rooms always read "0 members"

`memberCount` was seeded at 0 in `seedRooms()` and never written again, so the
number was structurally incapable of changing — including in the room you were
standing in.

Membership is now a real set (`rmem:<roomID>` in SocialDO) of everyone who has
opened or posted in a room, and `memberCount` is derived from it in the snapshot
rather than stored on the room record, so it can't drift. Opening a room calls
the new `POST /api/rooms/:id/join`; re-opening a room you're already in does not
bump the snapshot revision, so it doesn't wake every connected client. The
header reads "Just you so far" / "1 member" / "N members".

---

## Verification

- Worker: `tsc --noEmit` clean against the full `src/` (strict mode,
  `@cloudflare/workers-types`).
- Swift: reviewed by hand — no Swift toolchain is available in this session, so
  the Xcode build is the real check.
- Not covered: any message stored in the Lounge (not chat) *before* this change
  with "You" as its author is normalized going forward but not repaired on read
  the way chat messages are.
