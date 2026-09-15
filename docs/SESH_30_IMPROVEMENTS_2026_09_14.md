# The Sesh — 10 features and 20 polish improvements

Implemented September 14, 2026. Open **Track → Studio**, or **Me → Sesh Lab → Journal Studio**. This pass extends the existing journal; forecasts, strain matching, recap cards, rest-day planning, favorite categories, and the existing full-data export are not counted as new.

## Ten new features

| # | Feature | Implemented behavior | Evidence |
|---|---|---|---|
| 1 | Journal date windows | Browse today, the last 7/30/90 calendar days, or all time. Rolling windows include today and use local day boundaries. | `JournalStudioPolicy.includes`, `JournalStudioView.browse` |
| 2 | Method-specific journal browsing | Limit the journal to a recorded method and combine it with the other Studio filters. Saved methods that no longer exist remain visible as unavailable rather than silently changing the query. | `JournalStudioView.methods`, `matching`, `browse` |
| 3 | Saved journal views | Name and persist combinations of search, time, method, notebook, and pin filters. Recall or remove them independently of the journal. | `JournalStudioSavedView`, `savedViews`, `saveName` |
| 4 | Personal notebooks | Create named notebooks, put the same session into multiple notebooks, filter membership, and remove a notebook without deleting sessions. | `JournalNotebook`, `toggleMembership`, `entryRow` |
| 5 | Pinned sessions | Pin important sessions independently of the existing Favorites/strain rating category; browse just pinned sessions. | `JournalStudioSnapshot.pinned`, `togglePin`, `entryRow` |
| 6 | Reflection follow-up inbox | Choose a future date from a session's menu. The Reflect tab separates pending follow-ups, labels those ready to review, and supports completing/rescheduling them. These are in-app dates, not push notifications. | `JournalReflection.dueAt`, `pending`, `reflectionInbox`, `JournalReflectionEditor` |
| 7 | Guided private reflections | Add a separate reflection to an existing session using one of four prompts. Reopen and edit it without changing the original log. Draft dismissal is guarded, and a removed session cannot be recreated by an open reflection form. | `JournalReflection`, `JournalReflectionEditor`, `saveReflection` |
| 8 | Filtered CSV exports | Export the currently filtered session set to Files, with private notes excluded by default and an explicit inclusion switch. Photos, companions, and Studio reflections are excluded. Values are properly quoted and spreadsheet formula prefixes neutralized. | `JournalCSVDocument`, `exportOptions`, `makeCSV`, `JournalStudioPolicy.csvCell` |
| 9 | Two-session comparison | Pick two existing sessions and compare recorded dates, methods, amounts, ratings, durations, moods, effects, and notes. Missing data stays labeled missing. Deleting a selected log frees its comparison slot. | `selectComparison`, `comparisonContent`, `onChange` |
| 10 | Possible-duplicate review | Identify same-day logs with matching normalized strain, method, rating, and notes. Open each for review, mark a group as separate sessions, or restore dismissed matches. No auto-deletion and no claim that similar sessions are duplicates. | `duplicateGroups`, `duplicateReview`, `duplicateKey` |

## Twenty polish improvements

| # | Improvement | Evidence |
|---|---|---|
| 1 | Journal sort preference survives a relaunch. | `JournalView.sort` uses `@AppStorage` |
| 2 | Journal entries are no longer redundantly sorted before the unified feed's stable sort; obsolete parallel grouping was removed. | `JournalView.filtered`, `feed` |
| 3 | Journal header controls, result summaries, and group headings use scalable typography. | `JournalView` uses `seshScaled` |
| 4 | Filter headings, rating labels, and reset text scale with Dynamic Type. | `JournalFilterSheet` |
| 5 | Session-card title, timestamp, notes, and supporting metadata use scalable typography. | `SessionCard` |
| 6 | Long strain names get their own full-width line rather than competing with favorite and rating controls. | `SessionCard` title/action stacks |
| 7 | Session-type/duration and category/price metadata wrap instead of overflowing narrow cards. | `SessionCard` uses `FlowLayout` |
| 8 | Session note previews can grow vertically instead of always truncating at two lines. | `SessionCard` notes |
| 9 | Session favorite controls announce both their action and current state to VoiceOver. | `SessionCard.accessibilityLabel` / `accessibilityValue` |
| 10 | Session and thought swipe actions correctly say Unfavorite when already favorited. | `LogItemRow.swipeActions` |
| 11 | Journal search avoids automatic capitalization and uses the Search keyboard action. | `JournalView.searchBar` |
| 12 | Filter Reset has a 44-point target and is disabled when there is nothing to reset. | `JournalFilterSheet` |
| 13 | Selected effects have a checkmark as well as color, so selection is not color-only. | `JournalFilterSheet` effect labels |
| 14 | The filter sheet explicitly adopts the app's presentation background and tint. | `JournalView` filter sheet `seshEditorPresentation` |
| 15 | Removed a redundant 70-point blank journal footer; the shared root tab bar already supplies safe-area clearance. | `JournalView.feedList` |
| 16 | Sesh Lab destinations retain their native back navigation instead of hiding the only return control. | `SeshLabView.labLink` |
| 17 | Sesh Lab rows use scalable fonts and the shared 720-point maximum reading width on larger displays. | `SeshLabView` |
| 18 | Sesh Lab's introductory copy distinguishes personal tools from its optional shareable friend card. | `SeshLabView` |
| 19 | Weekly-spending buckets now use the current month, real month/day labels, and only finite nonnegative prices from that month; the old fixed May labels and all-month aggregation are gone. | `AppSession.weeklySpend`, `JournalStudioPolicy.monthlySpend` |
| 20 | Future-dated imported sessions no longer produce a negative “days since last session” count. | `AppSession.daysSinceLastSesh` |

## Data ownership and compatibility

- The Sesh owns and consumes this feature. No Worker, widget, social, or shared API/schema change is needed. The widget continues consuming the existing journal contract unchanged.
- `AppSession` remains authoritative for original logs. Studio stores only organization and reflection metadata in the protected, atomic local file `Application Support/JournalStudio/organization.json`. It uses journal UUIDs and never copies the original journal payload into another database.
- Saving publishes state only after disk succeeds. Corrupt/unknown-version metadata is preserved and shown as a recoverable error; it is never overwritten by an ordinary edit. The existing explicit journal/full reset erases Studio metadata too, even if unreadable.
- Entry deletion removes pins, notebook membership, and reflections for that UUID. Missing references are never used to resurrect deleted journal data.
- Studio metadata is **device-local**. It is not in the existing iCloud journal mirror, existing full-journal backup export, or public social payloads. Its CSV export is an explicit user-selected export of original sessions, not a complete Studio backup.
- The new filename is additive: no migration of existing sessions, categories, or thoughts. An older app version ignores Studio metadata. There is no server rollout or operator configuration.

## Validation

- Native `JournalStudioChecks`: **41 passed**. Covers calendar and DST boundaries, names, CSV quoting/formula protection, current-month totals, saved-view/reflection round trips, pin/membership changes, metadata deletion, corrupt-file preservation, explicit reset, and I/O failure without optimistic state mutation.
- Existing native `JournalUIContractChecks`: **65 passed**. Existing journal input, filtering, stable ordering, draft, social queue, and theme wiring contracts remain satisfied.
- Generic iOS build with shared `The SESH.` scheme: app and embedded `SeshWidgetExtension` compile. The build uses existing DerivedData; no simulator runtime was used.
- Simulator and device visual/interaction checks were not run, honoring the user's pause. Native compilation is not device visual verification. Physical-device acceptance should cover narrow/large-text cards, notebook filtering, reflection sheet dismissal, Files export, and deletion while comparison is open.
- Existing compiler warnings in unrelated Lounge/social/QA code are outside this pass.

Commands:

```sh
xcrun swiftc 'The SESH./Journal/JournalStudioPolicy.swift' 'The SESH./Journal/JournalStudioStore.swift' scripts/JournalStudioChecks.swift -o /tmp/sesh-journal-studio-checks
/tmp/sesh-journal-studio-checks
xcrun swiftc 'The SESH./CoreUI/JournalInputPolicy.swift' scripts/JournalUIContractChecks.swift -o /tmp/sesh-journal-ui-checks
/tmp/sesh-journal-ui-checks
xcodebuild -project 'The SESH..xcodeproj' -scheme 'The SESH.' -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```
