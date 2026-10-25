# PokerStats: specs for tips and add-ons, Lock Screen fold, and stack checks (#27-#30)

- **Author:** Mia (product), for Sam (manager) and the iOS and backend devs.
- **Status:** Draft for owner review. The owner decisions listed in section 4.4 are **open questions**, not decided.
- **Issues:** #27 (tips and add-ons), #28 (Live Activity spike), #29 (Lock Screen fold with Undo), #30 (stack checks and live P/L).
- **Originally based on:** `main` at `c717d4e` (Oct 18, 2026). Section 2 (stack checks) was rewritten for the 1.1 sync direction; see `docs/specs/1.1-sync.md` (merged in PR #97). The 1.1 sync spec sections cited in section 2.4 (8.3, 8.5, 10.2, 12 and 14) were checked against that file.

**Note on staleness.** Several "today's code" facts below were written against `c717d4e`. Since then `main` has changed:
- The CI crash from the force-unwrap in `AppGroupContainer` was fixed in PR #15 (`8cd03b1`). See the "Where the database lives" facts below and section 1.5; don't redo or undo that fix.
- Restore is atomic now (#32).
- Auto-restore runs once per device and is blocked by Delete All Data (#49).
- Delete Account wipes local data only after the server confirms, and it revokes the Apple token (#20, #23).

Re-check each [code] fact against current `main` before relying on it.

The three features:

1. **F1, Lock Screen fold button (#29, spike #28).** One-tap "Fold" on the Live Activity and Dynamic Island, with Undo. Shown only when auto-position is set up.
2. **F2, Stack checks and live P/L (#30).** Enter your stack during a session, see a live P/L in the app and on the Live Activity, and get a P/L-over-time chart in session detail. Stored as synced records in 1.1 Sync; no new backup format.
3. **F3, Tips and add-ons (#27).** Finish tips and add-ons: entry during and at the end of a session, editing, profit and hourly rate with and without tips.

How to read the labels:
- **[code]** means I checked it in the source.
- **[docs]** means it's from Apple documentation (links are in §5).
- **[verify]** means a dev has to confirm it on a device or in Xcode before relying on it.

---

## 0. TL;DR for sprint planning

| # | Feature | Effort | Changes the database or data format? | Hard dependencies |
|---|---|---|---|---|
| F3 (#27) | Tips and add-ons | **Small**: 2-3 dev-days, plus ~1 QA day | No. `tipRake` and `addOns` are already in the database **and** in the version-1 backup [code] | Open question for the owner: what "tips" means (section 3.4). Run #5 on a fixed build. |
| F1 (#29, #28) | Lock Screen fold and undo | **Medium**: 5-7 dev-days, plus ~2 QA days on a real device | No database or backup change. The Live Activity's data grows, using only optional fields. | CI green (the App Group crash is fixed in PR #15). Shared database refactor (section 1.6). |
| F2 (#30) | Stack checks and live P/L | **Medium**: 5-6 dev-days on top of sync, plus ~1.5 QA days | Yes: a new synced record type (stack checks) in the 1.1 sync data. **No backup format version 2.** | **The 1.1 sync work** (`docs/specs/1.1-sync.md`, technical design by Max). Lands after F1 because both edit the Live Activity. |

**Recommended order:** F3, then F1, then F2 (F2 after 1.1 sync). Rationale and calendar are in section 4.

---

## Shared facts about today's code (all [code])

**Live Activity**
- The Live Activity's data struct (`SessionActivityAttributes`) holds `stakes`, `location` and `startTime`. The part that updates (`ContentState`) holds only `handCount` and `totalInvested`.
- It has no session ID. `ActiveSessionViewModel.resumeOrStartLiveActivity()` finds the running activity by comparing `startTime`.
- That lookup doesn't check whether the activity is still active. `Activity.activities` can also return activities that have already ended but are still showing.
- `ActiveSessionViewModel` builds `ContentState` in 3 separate places (start, update, end). The Live Activity is display-only, with no buttons.

**Where the database lives**
- `AppGroupContainer.createSharedModelContainer()` builds a **new** database container (`ModelContainer`) every time it's called, stored at `<App Group>/PokerStats.store`.
- The app calls it once, in `PokerStatsApp.init`. The home-screen widget calls it again every time its data refreshes.
- `sharedContainerURL` returns `URL?` (changed in PR #15; it used to force-unwrap, which crashed CI under the test host with code signing turned off).
- `makeModelContainer(groupURL:isTestHost:)`: when the App Group folder is unavailable, a unit-test host falls back to an in-memory store, and any other launch throws `ContainerError.appGroupUnavailable`. There is deliberately no fallback to Application Support, so a signing or entitlement problem fails loudly instead of splitting the app's data from the widget's.

**How the database schema is handled**
- The schema (`Schema([Session.self, Hand.self, Settings.self])`) is listed three times: `AppGroupContainer`, `TestHelpers`, `PreviewSampleData`.
- It has no version or migration plan, so the database just upgrades itself automatically when fields are added. `Sprint2plan.md` proposed a migration plan, but it was never built.
- The widget extension compiles `Session.swift`, `Hand.swift`, `Settings.swift`, `Enums.swift`, `ComputedStats.swift`, `SessionActivityAttributes.swift`, `TableConfig.swift` and `AppGroupContainer.swift` (see `project.yml`).
- **Rule:** any new type that `Session` refers to must also be added to the widget's source list, or the widget won't build.

**Logging a hand**
- `ActiveSessionViewModel.addHand` does this: hand number = `session.nextHandNumber` (highest hand number + 1). If the table isn't calibrated yet, it works out where the button is from the hero's position. If it is calibrated, it moves the button on one seat (`PositionTracker.advanceButton`). Then it saves and updates the Live Activity.
- `deleteHand` does **not** move the button back. Swipe-to-delete on the latest hand already leaves auto-position one seat ahead today. That's an existing bug, and F1 fixes it as a side effect.

**View model lifetime**
- `SessionTabView` creates a **new** `ActiveSessionViewModel` every time its view body re-renders: `ActiveSessionView(viewModel: ActiveSessionViewModel(...))`.
- The view model's `init` has side effects: it resumes or starts the Live Activity and checks the 12-hour stale alert. Any new database write that triggers the session list query to refresh creates a new view model.

**Backup format**
- `BackupPayload.currentSchemaVersion = 1`. JSON keys are snake_case, dates are ISO 8601, and the file is zlib-compressed.
- `downloadBackup` throws `schemaVersionTooNew` when a file's version is higher than the app knows. This check runs **before** `restoreBackup` wipes local data. Optional fields in the backup data types decode as `nil` when the key is missing (standard Swift `Codable` behavior).
- `SessionDTO` already carries `addOns` and `tipRake`, and `Session.fromDTO` passes both through.

**Money**
- `netProfit = cashOut − (buyIn + rebuys + addOns)`. `tipRake` is ignored everywhere.
- `endSession(cashOut:tipRake: = 0)` is only ever called as `endSession(cashOut:)`. `abandonSession` doesn't set tips.
- So **every real session has `tipRake == 0`**. Only `DataSeeder` sets 5–25 (used by the DEBUG seed button and the `--seed-screenshot-data` screenshots).
- There's no add-on entry anywhere. `EndSessionSummaryView` shows add-ons only if > 0. The session detail financial card and edit sheet leave out add-ons and tips.

**What uses `netProfit` and `hourlyRate`**
- `StatCalculator.computeAll` (Dashboard, session stats)
- `TrendCalculator` (bankroll chart, day-of-week, P/L histogram, mental-state correlation)
- `SessionListViewModel.aggregateStats`
- `PokerStatsLifetimeWidget` (computes its own totals and streak)
- `EndSessionSummaryView`, `SessionDetailView` (including an inline ROI at line ~197), `SessionRowView`

**Leak Finder** uses no money fields: `statValue(for:)` reads only VPIP, PFR, c-bet, fold to 3-bet, WTSD and W$SD.

**Currency**
- `Settings.currency` is saved but ignored.
- `CurrencyFormatter` and `ComputedStats.formatCurrency` hard-code USD.
- The Live Activity uses the literal `"$\(Int(x))"`, and `CurrencyField` defaults its prefix to `"$"`.
- Money inputs use `.numberPad`, so whole dollars only. Edit fields are pre-filled with `String(Int(value))`, which drops any cents.

**Other**
- Nothing in the app watches `scenePhase` (whether the app is in the foreground or background). `SessionDetailViewModel.saveEdits` doesn't reload widgets (but `deleteSession` does).

---

# F1: Lock Screen and Dynamic Island fold button, with Undo

## 1.1 Problem and user story

Most live hands are preflop folds. Today every fold means unlock the phone, open the app, tap Log Hand, then tap Fold. That's one tap in auto-position mode; without it the position step comes first, so a fold is two taps [code]. At a live table, pulling the phone out and unlocking it is the slow, conspicuous part.

**User story:** "As a live player with auto-position set up, I want to log a fold from my Lock Screen or Dynamic Island with one tap, and undo it if I mis-tap, so I log every hand without unlocking or opening the app."

## 1.2 Scope

In scope:
- A **Fold** button on the Lock Screen Live Activity and the expanded Dynamic Island.
- An **Undo** button that removes the last fold logged from the Lock Screen.
- Shown only when the session is active, auto-position is calibrated, and the hero's position is known (`PositionTracker.heroPosition != .unknown`).
- A Settings toggle "Fold button on Lock Screen" (default **on**).
- Pulling the hand-logging and Live Activity code out into shared services that the app screens and the button actions both use.
- Fixing in-app delete of the latest hand so the button moves back too.

Not in scope:
- Calls, raises, results or notes from the Lock Screen. Those still go through the in-app logger.
- Any button when auto-position is off or not yet calibrated. No "unknown position" folds.
- Buttons on the compact or minimal Dynamic Island (Apple only allows buttons in the expanded and Lock Screen layouts [verify]).
- Push-driven Live Activity updates. All updates stay local.
- Apple Watch Smart Stack, CarPlay or Mac presentation. They may show the Live Activity automatically; treat that as untested [verify].
- Undo for anything other than the most recent hand logged from the Lock Screen.
- Restarting the Live Activity from the background after Apple's 8-hour limit (§1.8, pitfall 6).

## 1.3 UX flow and copy

**Lock Screen layout** (`PokerStatsLiveActivity.lockScreenView`)

Today's top row stays: stakes and location, hand count, timer and "$X in". Under it goes a new action row, shown only when quick fold is available:

```
[ Fold · BTN ]
```

After a quick fold, the row becomes:

```
Folded #42 · BTN        [ Undo ]
[ Fold · CO ]
```

**Dynamic Island, expanded**
- The bottom region has the same row: "Fold · CO", plus "Undo #42" if there is one. The current "Invested" line moves to the center or trailing region, or is shortened.
- Compact and minimal views don't change.

**Copy**
- Button: **"Fold · {POS}"**. Showing the position confirms that auto-position is in sync. If the position looks wrong, the user opens the app and corrects it with the existing position override.
- After a fold: **"Folded #{n} · {POS}"** and **"Undo"**.
- Settings: **"Fold button on Lock Screen"**, with the footnote "Log a preflop fold without unlocking. Only appears when auto-position is set up."
- In-app hint on the first calibrated hand, shown once: "Tip: you can now log folds from your Lock Screen."
- Accessibility labels: "Log fold, position Button", "Undo fold, hand 42".

**HIG notes**
- Keep the Live Activity to essential actions. One main action (Fold) and one way back (Undo) fits Apple's guidance [verify against the current HIG Live Activities page].
- Tap targets should be at least 44×44 pt.
- Make the actions visually distinct: Fold in neutral fill, Undo as a bordered secondary style.
- Live Activity buttons can't vibrate. Confirmation is the label changing to "Folded #n".
- Don't make the Lock Screen layout so tall that it gets clipped. Apple caps its height [verify the current limit, ~160 pt].
- Test at the largest Dynamic Type.

**State rules**

| Condition | Fold shown | Undo shown |
|---|---|---|
| Session active, auto-position calibrated, hero position known, setting on | Yes | If the last hand was a Lock Screen fold and is still the latest hand |
| Not calibrated (before the first in-app hand) or auto-position off | No | No |
| Session ended or abandoned | No (final state has no buttons) | No |
| Setting off | No | No |

## 1.4 Data model and migration

- **Database:** no schema change. A Lock Screen fold is an ordinary `Hand(preflopAction: .fold, position: heroPosition)`.
  - Optional: add `var source: String?` ("lockScreen") for analytics or debugging. **Recommendation: don't.** If it's ever wanted, add it as a hand field in the 1.1 sync data (Max's design), not as a backup format change.
- **Backup format:** no change, still version 1.
- **The Live Activity's data, `SessionActivityAttributes`:**
  - Attributes: add `let sessionID: UUID?`. It's optional so activities that were running before the update still decode [verify on device by updating mid-session].
  - Updating data, all new fields optional:
    ```swift
    struct ContentState: Codable, Hashable {
        let handCount: Int
        let totalInvested: Double
        // F1
        var nextHandNumber: Int? = nil
        var quickFoldPosition: String? = nil   // SeatPosition.rawValue; nil = hide Fold
        var undoHandID: UUID? = nil
        var undoHandNumber: Int? = nil
        var undoPosition: String? = nil
        // F2 adds livePL / livePLAsOf here (optional)
    }
    ```
  - Keep it far under Apple's 4 KB limit [docs]. No player names, no table setup in the Live Activity's data.
- **Undo bookkeeping, not in the database:** a small `QuickFoldUndoRecord {handID, sessionID, buttonSeatBefore}` stored in App Group `UserDefaults` (key `quickFold.lastUndo`).
  - Why: undo has to put the button back exactly where it was. `buttonSeatBefore` is one integer.
  - Clear the record whenever any other hand is logged or deleted, the session ends, or a restore or Delete All runs.
- **Settings toggle:** App Group `UserDefaults` key `quickFold.enabled` (Bool, default true). It's a per-device preference, isn't backed up, and needs no database or backup change.

## 1.5 Code touchpoints

New files:
- `PokerStats/Services/HandLoggingService.swift`
  - `@MainActor enum HandLoggingService`
  - `log(_ hand:in session:context:) throws -> LoggedHand`. This is today's `addHand` logic moved here: assign the number, calibrate or move the button, save. It returns `buttonSeatBefore` so undo can restore it.
  - `quickFold(sessionID:expectedHandNumber:context:) throws -> QuickFoldOutcome`, where the outcome is `.logged(Hand)`, `.ignoredStale`, `.ignoredNotEligible`.
  - `undoQuickFold(handID:context:) throws -> UndoOutcome`.
  - `deleteHand(_:in:context:) throws`. It moves the button back if the hand is the latest one and the table is calibrated.
- `PokerStats/Services/LiveActivityController.swift`
  - `@MainActor enum`.
  - `activity(for session:)` matches on `sessionID`, falls back to `startTime`, and **only returns activities that are still active**.
  - `makeState(for session:) -> ContentState` is the one place the data is built.
  - Also `start`, `update(session:)`, `end(session:)`.
- `PokerStats/Intents/QuickFoldIntents.swift`
  - `struct QuickFoldIntent: LiveActivityIntent` with `@Parameter sessionID: String` and `@Parameter expectedHandNumber: Int`.
  - `struct UndoQuickFoldIntent: LiveActivityIntent` with `@Parameter sessionID: String`, `@Parameter handID: String`.
  - Both use `static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed` [docs], and `@MainActor func perform() async throws -> some IntentResult`.
  - Intent parameters come from the Live Activity and are untrusted input. `perform` validates them against the database and the stored undo record and does nothing when they don't match (see the Undo steps below and §1.9).

Changed files:
- `Services/PositionTracker.swift`: add `restoreButton(config:toSeat:) -> TableConfig`.
- `Services/AppGroupContainer.swift`
  - Add `@MainActor static let shared: ModelContainer`, created lazily once.
  - Build `shared` with the existing `createSharedModelContainer()`. Keep its current App Group handling (superseded item, already merged in PR #15): no force-unwrap, in-memory store only for a unit-test host, `ContainerError.appGroupUnavailable` otherwise. Don't add an Application Support fallback.
- `App/PokerStatsApp.swift`: use `AppGroupContainer.shared` instead of creating its own container. Add a `scenePhase` observer: when the app becomes active, refresh the session data and the Live Activity.
- `ViewModels/ActiveSessionViewModel.swift`: `addHand`, `deleteHand` and the Live Activity methods delegate to the new services. Remove the 3 copies of the `ContentState` builder.
- `Views/Session/ActiveSessionView.swift`
  - Swipe-delete goes through `HandLoggingService.deleteHand`.
  - When the app comes back to the foreground with the logger sheet open, reset or re-configure `handLogger` if `session.nextHandNumber` changed since the sheet opened (pitfall 7).
- `Views/Session/SessionTabView.swift`: hold the view model in `@State` keyed by `session.id`, so it isn't rebuilt every time the view re-renders (pitfall 9).
- `Models/SessionActivityAttributes.swift`: add the fields from §1.4.
- `PokerStatsWidgets/PokerStatsLiveActivity.swift`: add the action row using `Button(intent: QuickFoldIntent(...))` and `Button(intent: UndoQuickFoldIntent(...))`.
- `Views/Settings/SettingsView.swift` (and `SettingsViewModel`): add the toggle, backed by App Group `UserDefaults`.
- `project.yml`
  - Add `QuickFoldIntents.swift` to **both** targets. The widget needs the intent type to build the button, but the action itself runs in the app [docs].
  - The intent's `perform` would then also compile in the widget. Pick one of two options:
    - (a) Add `HandLoggingService.swift`, `LiveActivityController.swift` and `PositionTracker.swift` to the widget's sources too. They're pure Swift and type-check everywhere. **Recommended.**
    - (b) Add a `WIDGET_EXTENSION` compile flag to the widget target and wrap the `perform` body in `#if !WIDGET_EXTENSION`.
- `README.md`: fix the "Fold preflop = 1 tap" row. It's 2 taps in manual mode, 1 in auto-position mode, and 1 tap from the Lock Screen. Also add the feature.
- Tests: new `HandLoggingServiceTests.swift` and `LiveActivityStateTests.swift`, plus additions to `PositionTrackerTests.swift`.

**What the Fold button does, step by step**
1. Get `context = AppGroupContainer.shared.mainContext`. Never create a second container.
2. Parse `sessionID` as a UUID. If it doesn't parse, do nothing and return: no write, no button move. Then fetch the session by that ID. If it's missing or not active, end or refresh the Live Activity and return.
3. Check the setting, that auto-position is calibrated, and that the hero position isn't unknown. Otherwise refresh the Live Activity so the button disappears, and return.
4. If `session.nextHandNumber != expectedHandNumber`, refresh the Live Activity and return. This is how double taps and stale buttons are ignored.
5. Build `Hand(preflopAction: .fold, position: heroPosition)` and call `HandLoggingService.log`. It assigns the number, moves the button, and saves; if the save fails it calls `context.rollback()`.
6. Write the undo record `{handID, sessionID, buttonSeatBefore}`.
7. `await LiveActivityController.update(session:)`.
8. No backup and no network calls (backup still happens only at session end). No home-screen widget reload, since that widget only shows completed sessions.

**What Undo does, step by step**
1. Load the undo record and check that both `handID` and `sessionID` parse as UUIDs and match it. If not, do nothing: no delete, no button move.
2. Check that the hand still exists and is still the **latest** hand in that session (`handNumber == max`). If not, clear the record, refresh, and return.
3. Delete the hand and put the button back to `buttonSeatBefore`. Save, clear the record, and update the Live Activity.

## 1.6 Prerequisite refactor: one shared database container

**Why it matters**
- The fold button's action runs in the app's process [docs].
- If it opens its own container on the same database file, the app's open screens won't see the new hand until they re-fetch. Apple's developer forums document this exact symptom; a re-fetch after coming back to the foreground fixes it on iOS 18+ [docs/forums].
- One `AppGroupContainer.shared` used by the app and the button actions means one `mainContext` and one `Session` object in memory. Hand numbers can't race.

**What to keep as is:** the home-screen widget runs in its own process and keeps creating its own container. It only reads, so that's fine.

## 1.7 Acceptance criteria

1. With auto-position calibrated (position shown in the Table tile), locking the phone shows "Fold · {POS}" on the Lock Screen within ~1 s of the last in-app action.
2. Tapping Fold while locked, without Face ID, adds exactly one hand: `.fold`, the correct next hand number, the position that was shown. The button moves on one seat, and the Live Activity then shows "Folded #n · POS", "Undo", and "Fold · {next POS}".
3. Five fast taps on Fold add **at most one** hand per Live Activity refresh. Hand numbers never repeat or skip.
4. Undo removes that hand and puts the button back. The next Fold shows the original position and reuses the hand number.
5. After any other hand is logged or deleted in the app, Undo disappears and an old Undo button does nothing.
6. With auto-position off or not calibrated, or the setting off, no Fold button appears. Tapping an old one does nothing and the Live Activity refreshes.
7. After force-quitting the app, a Fold tap still logs the hand. Opening the app afterwards shows it in Recent Hands without restarting the app.
8. Opening the app after Lock Screen folds shows the correct hand count, Recent Hands and position. A logger sheet that was left open re-configures itself to the current position.
9. Ending or abandoning the session removes both buttons from the final Live Activity.
10. Swipe-deleting the latest hand in the app moves the button back one seat; deleting an older hand doesn't.
11. Existing in-app logging is unchanged: same taps, same timing. `HandLoggerViewModel` has zero diff.
12. All existing tests and the new tests pass in CI (`.github/workflows/ci.yml`, added in PR #15).

## 1.8 Pitfalls and mitigations

1. **Which process runs the button.** `LiveActivityIntent.perform` runs in the **app** process, not the widget [docs]. If the intent type is only in the widget target, the button silently does nothing.
   - Add the file to both targets. Test from a fresh install on device.
2. **App killed or suspended.** The system wakes or launches the app in the background to run the action [docs]. If it's a fresh launch, `PokerStatsApp.init` may or may not run first [verify].
   - The lazily created `AppGroupContainer.shared` works either way.
   - Keep the action short: no network, no backup, no sleeps.
   - Don't rely on `ActiveSessionViewModel` existing.
3. **SwiftData concurrency across the App Group database.**
   - Never create a second container or context in the app process for this.
   - Do every write on `@MainActor` through `shared.mainContext`, and save before updating the Live Activity.
   - If the save fails, call `rollback()` and leave the Live Activity as it was.
   - The widget process only reads. Never write from the widget.
4. **Double taps and debouncing.** A Live Activity can't disable a button between tap and redraw.
   - Every Fold carries `expectedHandNumber`. The action ignores the tap unless it equals `session.nextHandNumber`, which makes it idempotent.
   - Undo carries `handID`. A second Undo finds nothing and does nothing.
   - No timers needed.
5. **Live Activity update limits and stale content.**
   - Updates made locally by the app (which is all we do) aren't the same as push updates, which have a documented budget. The system can still delay or merge them [verify on device with rapid taps].
   - Update only after a real change, never on a timer. The timer already ticks by itself via `Text(startTime, style: .timer)`.
   - The 4 KB data limit applies [docs]. Keep the data to small numbers and short strings.
   - Leave `staleDate` nil, since there's no external data to go stale.
6. **The 8-hour limit.** Apple ends a Live Activity after 8 hours. It disappears from the Dynamic Island right away and stays on the Lock Screen for up to 4 more hours, frozen [docs]. Long live sessions will lose the Fold button.
   - `LiveActivityController.activity(for:)` must ignore activities that have ended. Today's lookup by `startTime` doesn't, which would silently update a dead activity.
   - When the app comes back to the foreground, start a new activity if the session is still active and no live one exists.
   - Optional copy in the app: "Lock Screen controls pause after 8 hours. Open PokerStats to restore them."
7. **Hand number and button-move race while the app is also open.**
   - The race goes away with one shared context on the main actor.
   - The leftover risk is a logger sheet opened *before* a Lock Screen fold. It was set up with the old position, and finishing it would save the old position and move the button again. This can happen if the user opens the sheet, locks the phone, taps Fold, then unlocks.
   - When the app comes back to the foreground, compare the hand number the sheet started with against `session.nextHandNumber`. If they differ, call `handLogger.reset()` and `configureAutoPosition` again, with a small banner: "Hand #42 was logged from the Lock Screen."
8. **Undo semantics.** Undo only applies to the last hand logged from the Lock Screen, and only while it's still the latest hand.
   - Put the button back to the exact seat it was on (`buttonSeatBefore`), not "one seat back". Seats may have been added or removed in between.
   - Clear the undo record whenever a hand is logged or deleted, a session ends, or the database is restored or deleted.
   - Never remove a hand logged in the app via the Lock Screen Undo.
9. **View model rebuilt every render.** A database write from the button refreshes the session list query, which re-renders `SessionTabView` and creates a new view model. Its `init` side effects (start or resume the Live Activity, stale alert) run again.
   - Hold the view model in `@State` keyed by session ID.
   - Make the Live Activity start/resume idempotent through `LiveActivityController`.
10. **Behavior while locked.**
    - Set `authenticationPolicy = .alwaysAllowed` [docs], or the system will ask for Face ID and kill the one-tap value. With no Face ID, Fold and Undo parameters are untrusted: validate them as in §1.5 and §1.9.
    - Database file protection: keep the iOS default (`completeUntilFirstUserAuthentication`) on the store, including the SwiftData store's `-wal` and `-shm` sidecar files, and never lower it to `none`. Don't raise it to full (`complete`) either, or writes fail while locked. Test after a reboot **before the first unlock**: writes will probably fail [verify]. In that case the action should fail gracefully and leave the Live Activity unchanged. The same test confirms that no store file, sidecars included, was created with a different protection class.
11. **Swift 6 strict concurrency** (`SWIFT_STRICT_CONCURRENCY: complete` on both targets [code]).
    - Mark `perform` `@MainActor`.
    - Keep `@Parameter` types as `String`/`Int`, and convert to `UUID` inside.
    - `ModelContext` and `@Model` objects aren't `Sendable`, so don't pass them across tasks. Keep the `@preconcurrency import ActivityKit` pattern.
    - Make `AppGroupContainer.shared` a `@MainActor static let`.
12. **Getting the wrong activity.** With several activities (ended and active) for the same app, matching by `startTime` alone is fragile.
    - Add `sessionID` to the attributes, and fall back to `startTime` for activities started before the update.
13. **Activities started before an app update.** Their data has no `sessionID` and no new fields.
    - All new fields are optional, and a decode test is required (§1.9).
    - The first time the app comes to the foreground after the update, it can end the old activity and start a new one.
14. **Restore or Delete All while a session is active.** `BackupService.restoreBackup` and `deleteAllData` wipe sessions [code]. A frozen Fold button could then point at a session that no longer exists.
    - The action handles a missing session by ending the activity.
    - Clear the undo record on restore and on delete.
15. **Accidental taps at the table** (a pocketed phone, someone else's hand).
    - The position label, Undo, and the Settings toggle cover this. Prefer `.alwaysAllowed` for speed, but document it. Revisit if QA sees phantom folds.
    - An Undo can only remove the hand named in the stored undo record, and only while it's the latest hand (§1.9 tests).
16. **Protecting the under-3-second promise.** None of this may add a step to the in-app logger. Diff `HandLoggerViewModel` and keep it to zero changes.
17. **App Review.** No real risk for buttons on Live Activities. Don't add marketing or upsell content to the Live Activity.
18. **Privacy.** The Lock Screen already shows stakes, location and amount invested [code]. Adding position doesn't add sensitive data. F2's P/L does (see there).

## 1.9 Test plan

**Unit tests (Swift Testing, in-memory container from `TestHelpers`; never touch `AppGroupContainer.shared` in tests)**
- `HandLoggingServiceTests`
  - `quickFold_logsFoldWithNextNumberAndHeroPosition`
  - `quickFold_advancesButton`
  - `quickFold_wrongExpectedNumber_isNoOp`
  - `quickFold_notCalibrated_isNoOp`
  - `quickFold_unknownPosition_isNoOp`
  - `quickFold_inactiveSession_isNoOp`
  - `quickFold_missingSession_isNoOp`
  - `quickFold_malformedSessionID_isNoOp`: a `sessionID` that isn't a valid UUID logs no hand, leaves the button where it is, and writes no undo record.
  - `undo_removesHandAndRestoresButtonSeat`
  - `undo_afterAnotherHand_isNoOp`
  - `undo_twice_isNoOp`
  - `undo_handIDNotMatchingRecord_isNoOp`: an `UndoQuickFoldIntent` whose `handID` differs from the stored undo record deletes nothing and leaves the button where it is.
  - `undo_handNotLatest_isNoOp`: `handID` matches the record but a later hand exists in the session (for example one that arrived by sync). Nothing is deleted, the button doesn't move, and the record is cleared.
  - `undo_sessionIDNotMatchingRecord_isNoOp` and `undo_malformedHandID_isNoOp`: no change.
  - `undo_afterSeatsChanged_restoresExactSeat`
  - `deleteLatestHand_restoresButton`
  - `deleteOlderHand_doesNotMoveButton`
  - `log_matchesLegacyAddHandBehavior`: calibration on the first hand, then advance.
- `PositionTrackerTests`: `restoreButton` cases for heads-up, 6-max, 9-max, and an empty seat.
- `LiveActivityStateTests`
  - Decode a hard-coded old JSON `{"handCount":3,"totalInvested":200}` into the new `ContentState`. Do the same for old attributes without `sessionID`.
  - `makeState` hides Fold when not eligible and shows Undo only when the record matches the latest hand.
  - Encoded size < 1 KB.

**Manual end-to-end on a physical iPhone with Dynamic Island, iOS 26**

Setup:
- Use a 6-max table.
- Log the first hand in the app as BTN to calibrate. Check that the Table tile shows the hero's position.

1. Lock the phone and tap Fold. The Live Activity shows "Folded #2 · {pos}". Unlock: Recent Hands shows #2, and the position tile has moved on.
2. Tap Fold 5 times as fast as possible. Count the hands in the app: it should match the number of visible "Folded #n" changes, with no duplicate numbers.
3. Tap Undo. The hand is removed and the next Fold shows the previous position. Tap Undo again: nothing happens.
4. Fold from the Lock Screen, then log a hand in the app. The Undo button is gone.
5. Force-quit the app from the app switcher, lock the phone, tap Fold. Reopen: the hand is there.
6. Open the logger sheet, lock the phone, fold from the Lock Screen, unlock. The sheet re-configures and the banner shows.
7. Expanded Dynamic Island while using another app: Fold and Undo work.
8. Turn the setting off: the button disappears on the next refresh. Disable auto-position (manual position session): no button.
9. End the session: the final Live Activity has no buttons. Abandon the session: same.
10. Reboot and, before first unlock, tap any frozen button. The app doesn't crash and no partial hand appears [verify].
11. Install the old build, start a session, update to the new build mid-session, and open the app. The Live Activity keeps working or is replaced cleanly.
12. Largest Dynamic Type and VoiceOver labels read correctly.
13. Long session: either simulate by ending the activity from a debug menu, or run 8 hours on a spare device. After the app returns to the foreground, a new activity appears.

**Effort: Medium, 5–7 dev-days plus ~2 QA days on device.** Breakdown:
- Shared container (the CI-safe App Group handling already merged in PR #15): 0.5 day
- Services extraction: 1–1.5 days
- Button actions and Live Activity UI: 1.5–2 days
- Foreground re-sync, view model lifetime fix: 1 day
- Tests: 1 day
- Plus a 0.5-day spike up front (§4.5)

---

# F2: Stack checks, live P/L, P/L chart in session detail (#30)

## 2.1 Problem and user story

During a session the app only knows money in. `runningProfitLoss` is literally `-session.totalInvested` [code], and the Live Activity shows "$X in". Players can't see how they're doing mid-session or how a session swung. Competitors track this:
- Poker Analytics 6.7: stack tracking with a graph
- Poker Stack: "stack checks"
- A Poker Bankroll Tracker reviewer praises in-session stack tracking

**User story:** "As a live player, I want to tap in my current stack whenever I feel like it, see my live P/L in the app and on my Lock Screen, and later see how my P/L moved over the session."

## 2.2 Scope

In scope:
- Enter a stack check from the active session screen.
- A live P/L tile in the app.
- Live P/L, with how long ago it was checked, on the Lock Screen and expanded Dynamic Island, behind a toggle.
- Delete a mistaken check during the session.
- A "Session P/L" chart in session detail.
- A "Use last stack" shortcut in the end-session sheet.
- Stack checks stored and synced as records in the 1.1 sync data (private per user).

Not in scope:
- Reminders or auto-prompts to enter your stack.
- Stack entry inside the hand logger (never).
- Stack entry from the Lock Screen. Typing on a Live Activity isn't possible.
- Editing stack checks after the session ends.
- "Optimal session length" analytics.
- A per-rebuy timeline (rebuys stay a single sum).
- Tournament chip stacks (that's issue #8).
- A new snapshot backup format. There is no backup version 2; stack checks are not added to version-1 backups.
- Fixing the currency setting.

## 2.3 UX flow and copy

**Active session status bar** (`ActiveSessionView.sessionStatusBar`). Today it has three tiles: Invested, Hands, Table. Add a **Live P/L** tile:
- No checks yet: "Live P/L" / "**Add stack**" (accent color).
- After a check: "Live P/L" / "**+$140**" (green or red), with caption "as of 9:42 PM".
- Tapping it opens the stack sheet.
- Why a tile: the action row already has 4 buttons (Rebuy, Check In, Note, End) [code]. A 5th would crowd the 6.1" iPhone 16e that's in the Snapfile. Test the tile row at the largest Dynamic Type; if needed, put "Invested" under the P/L as a caption.

**Stack sheet** (`.presentationDetents([.height(300)])`, same pattern as the rebuy sheet)
- Field: **"Current stack"** using `CurrencyField` with `.numberPad`, in focus when the sheet opens.
- Live preview under it: "Live P/L: **+$140**" (stack − invested).
- Primary button: **"Save Stack"**.
- Below: the last 3 checks ("9:42 PM · $740 · +$140"), swipe to delete.
- Validation messages:
  - Empty field: Save disabled.
  - Above 20× invested: inline warning "That's 25× what you've put in. Double-check the amount." (Save still allowed).
  - Above 10,000,000: blocked, "That amount looks wrong."
  - Stack 0 (busted): allowed, with the hint "Add a rebuy or end the session?". It's a hint, not a prompt.

**After a rebuy:** P/L doesn't change, because buying chips doesn't change profit (§2.4). The tile caption becomes "as of 9:42 PM · rebuy since". The estimated stack is last stack + rebuys since that check.

**End session sheet:** if a check exists, show a chip **"Use last stack ($740)"** (the estimated current stack). Tapping it fills the cash-out field. **Never pre-fill silently.**

**Live Activity** (setting **"Show live P/L on Lock Screen"**. The default, on or off, is an open question for the owner; see pitfall 6 and section 4.4.)
- Lock Screen: replace "$X in" with "**+$140** · 12m ago" (`Text(asOf, style: .relative)`), or keep "$X in" until there's a check.
- Expanded Dynamic Island: bottom region shows Live P/L and Invested. If F1 is in, it's one row with Fold.

**Session detail, "Session P/L" card** (only if the session has at least 1 check)
- Swift Charts `LineMark` plus `PointMark` of P/L over time, with a `RuleMark` at 0.
- Points: start (0 at `startTime`), each check, and the end (`netProfit` at `endTime`, labeled "Cash out", or "Abandoned" if abandoned).
- Tap or drag on a point shows "9:42 PM · stack $740 · +$140".
- Why P/L instead of raw stack: raw stack jumps on every rebuy and misleads. Whether to also offer raw stack (a two-option picker, P/L | Stack) is an open question for the owner. It's cheap, but this spec leaves it out of the first version.
- Use the same chart style as `TrendsView` (`.pokerCard()`, colors from `PokerTheme`).

**HIG notes**
- The primary action sits at the bottom, reachable with a thumb. Cancel goes in the toolbar.
- Don't show the P/L in color only: keep the +/− sign for color-blind users.
- Charts get an accessibility summary ("P/L ranged from −$200 to +$340, ended +$140").

## 2.4 Data model and sync

Stack checks are **records in the 1.1 sync data**, not a field inside a backup file. The schema and sync mechanics are Max's technical design; this section states what the data must hold and how it behaves.

**What a stack check holds**
- `id` (stable UUID, created on the device)
- the session it belongs to
- `timestamp`
- `stack`: chips in front of you, in money units
- `topUpsAtCheck`: `session.rebuys + session.addOns` at the moment of the check

**P/L at a check** = `stack - (session.buyIn + topUpsAtCheck)`.
- `buyIn` is read live, so fixing a buy-in typo later still gives correct numbers.
- `topUpsAtCheck` is a snapshot, so a later rebuy doesn't change earlier checks.
- The current estimated stack = `last.stack + (session.rebuys + session.addOns - last.topUpsAtCheck)`.
- These formulas must be identical on iOS and web (1.1 sync spec, section 12, "Stats parity between iOS and web").

**Sync behavior** (follows `docs/specs/1.1-sync.md`)
- Private per user, like sessions and hands. Nothing is visible to other users.
- Created offline and queued like hands. Saving a check never waits for the network.
- Only the session's logging device adds checks (1.1 sync spec, section 8.3, "An active session on two devices"). Other devices see them read-only.
- Deleting a check during the session deletes it everywhere. Deleting a session deletes its checks, and restoring the session from Recently Deleted restores them.
- Delete All Data ("Delete from all devices") and Delete Account remove them from the server.
- An older app version that doesn't know stack checks must not delete them, or it stops syncing with "Update PokerStats to keep syncing" (1.1 sync spec, section 8.5, "Different app versions").

**Server-side controls** (required in the same PR that adds the stack checks Supabase table; Kate blocks any migration without them)
- Enable row-level security on the table, with policies that limit every row to its owning user.
- Include tests proving that one user cannot read, insert, update or delete another user's stack checks.
- Delete Account removes them: either the `delete-account` edge function deletes them, or the table uses `ON DELETE CASCADE` from a row that function already deletes. State which in the PR.
- The 1.1 Delete Account end-to-end test (1.1 sync spec, section 10.2 and section 14, criterion 13) checks that no stack checks remain on the server for the deleted account. Criterion 13 in the 1.1 sync spec doesn't name stack checks yet, so the PR that adds the stack checks table must also extend criterion 13 or the Delete Account E2E test plan to cover them.

**On the device**
- How stack checks are stored locally (a new SwiftData model linked to `Session`, or a field on `Session`) is decided together with the 1.1 sync design. Per-record sync favors a separate model with its own ID and cascade delete.
- If a new type is referenced by `Session`, add it to the widget's sources in `project.yml`.
- Any schema change must keep opening an existing database without data loss [verify by opening a database created by the current build with the new build].
- Compute chart series once in the view model, not inside the view body.

**Snapshot backups:** no change. There is no backup version 2, `BackupPayload.currentSchemaVersion` stays 1, and the 1.1 sync spec stops new snapshot backups for syncing accounts. A user who is not signed in has stack checks on the device only, like all their other data.

## 2.5 Code touchpoints

- Stack check model (new; local storage form per the 1.1 sync design). `Models/Session.swift`: add `stackChecks`, `latestStackCheck`, `livePL`, `estimatedCurrentStack`.
- The 1.1 sync layer (Max's design): register stack checks as a synced record type.
- `project.yml`: add the new model file to the `PokerStatsWidgets` sources if `Session` refers to it.
- `ViewModels/ActiveSessionViewModel.swift`
  - Add `isShowingStackSheet`, `stackAmountText`, `addStackCheck()`, `deleteStackCheck(id:)`.
  - Replace `runningProfitLoss` with `session.livePL`.
  - `addRebuy()` already triggers a Live Activity update.
- `Views/Session/ActiveSessionView.swift`: add the Live P/L tile, the stack sheet (inline or a new `StackCheckSheet.swift`), and the "Use last stack" chip in `endSessionSheet`.
- `Models/SessionActivityAttributes.swift`: `ContentState` gets `var livePL: Double? = nil` and `var livePLAsOf: Date? = nil`.
- `Services/LiveActivityController.swift` (from F1): include the P/L when the toggle is on.
- `PokerStatsWidgets/PokerStatsLiveActivity.swift`: show the P/L. Use `ComputedStats.formatCurrency` (already in the widget target), **not** a `"$"` literal.
- `Services/StackCalculator.swift` (new, pure): `stackSeries(session:) -> [StackPoint]`.
- `ViewModels/SessionDetailViewModel.swift`: `stackSeries`, computed once. `Views/History/SessionDetailView.swift`: the "Session P/L" card (`import Charts`).
- `Views/Settings/SettingsView.swift`: "Show live P/L on Lock Screen" toggle, in App Group `UserDefaults` (`livePL.onLockScreen`), device-only (never synced).
- `Services/DataSeeder.swift`: add 2–5 checks to seeded sessions so the chart appears in demo data.
- Tests: `StackCheckTests.swift`, `StackCalculatorTests.swift`, and stack-check cases in the sync test suite.

## 2.6 Acceptance criteria

1. A new session shows "Live P/L · Add stack". Saving a stack of 740 with invested 600 shows "+$140 · as of {time}" right away. The Live Activity updates within ~1 s.
2. After a rebuy of 200, the live P/L **still** shows +$140, and the estimated stack is $940. A new check of 900 shows −$100 (invested 800).
3. Deleting the latest check falls back to the previous check's P/L, or to "Add stack".
4. An empty or non-numeric amount can't be saved. Above 20× invested shows a warning; above 10,000,000 is blocked.
5. Hand logger tap counts and timing are unchanged. The stack sheet never opens automatically.
6. "Use last stack" fills the cash-out only when tapped.
7. Session detail shows "Session P/L" with start, checks, and end points. The end point equals `netProfit`. Sessions without checks show no card.
8. With the setting off, the Live Activity shows no P/L.
9. Sync:
   - A check saved offline appears on a second signed-in device after both are online, with identical values.
   - Deleting a check, or its session, removes it on the other device.
   - The other device shows checks read-only while the session is logging elsewhere.
   - No snapshot backup changes: `schema_version` stays 1 and `stack_checks` never appears in a backup.
10. Opening a database file created by the current `main` build with the new build doesn't crash and keeps all data.
11. CI is green.

## 2.7 Test plan

**Unit tests**
- `StackCheckTests`
  - P/L math, including that a later rebuy doesn't change an earlier check's P/L
  - Estimated stack after rebuys and add-ons
  - Editing buy-in moves the P/L correctly
  - Local storage round trip of stack checks (whichever form the 1.1 sync design picks)
  - `latestStackCheck` ordering with timestamps out of order
  - Validation helper (empty, 0, negative, above the hard cap, above 20×)
- `StackCalculatorTests`
  - Start point at 0
  - End point = `netProfit` for completed sessions, absent for active ones
  - Abandoned session ends at −invested
  - Duplicate timestamps
- Sync tests (with the 1.1 sync suite): create, delete and cascade-delete of stack checks; an unknown-record-type case for older clients.
- Server tests (in the PR that adds the table): RLS denies another user's read, insert, update and delete; Delete Account leaves no stack checks (section 2.4, server-side controls).
- `LiveActivityStateTests`: an old JSON without `livePL` still decodes. The P/L is left out when the setting is off.

**Manual end-to-end (two devices, signed in; needs 1.1 sync)**
1. On the **current** build, create sessions. Install the new build over it: the database opens and data is intact.
2. Add checks on device A while offline, end the session, reconnect: device B shows the same checks and the same chart.
3. Delete the session on A: its checks are gone on B. Restore it from Recently Deleted: the checks come back.
4. Delete Account once: the server has no stack checks left for that account.
5. At-the-table flow: rebuy, then check, then Live Activity P/L, then lock and glance. Toggle the setting off.
6. Small iPhone (16e) at the largest Dynamic Type: the status tiles don't clip.

**Effort: Medium, 5–6 dev-days plus ~1.5 QA days.** Breakdown:
- Model and sync integration (on top of the 1.1 sync layer): 1.5 days
- Active session UI and validation: 1.5 days
- Live Activity: 0.5 day (building on F1's controller)
- Chart: 1 day
- Tests and seed data: 1 day

## 2.8 Pitfalls and mitigations

1. **Opening an existing database after the update.** There's no migration plan; we rely on the automatic upgrade for additive changes [code]. Coordinate any schema versioning with the 1.1 sync design.
   - Keep new fields optional and add **no** non-optional stored properties without defaults.
   - Don't rename stored properties.
   - Do the manual test of opening a database made by the old build.
2. **Sync correctness.** Stack checks follow the 1.1 sync rules: per-record IDs, queued offline, deletes cascade with their session.
   - Test that an older client never removes stack checks it doesn't understand.
3. **Older app versions.** Handled by the 1.1 sync version rule (update required to keep syncing). There's no backup version bump, so there's no restore refusal to document.
4. **Never slowing the hand logger.**
   - No changes to `HandLoggerViewModel` or `HandLoggerSheet`.
   - No stack prompt after hands.
   - The stack sheet is only reachable from the status tile.
   - The stack sheet and logger sheet are separate `.sheet`s on the same view; SwiftUI shows one at a time, so make sure one dismisses before the other can open.
5. **Rebuys and the stack.**
   - Store `topUpsAtCheck` so the P/L stays correct after a rebuy without a new check.
   - Plot P/L, not raw stack.
   - Don't auto-create a check on rebuy (it would be a guess).
   - Rebuys edited after the session can't be placed in time. Document that the chart's end point always uses the actual cash-out.
6. **Privacy at the table (Lock Screen P/L).** Neighbors can see your Lock Screen, and some players don't want their win or loss visible.
   - Settings toggle. Consider defaulting to **off**, or redacting while locked. Whether `.privacySensitive()` redacts inside Live Activities is [verify].
   - **Open question for the owner:** default on or off.
7. **How often the Live Activity updates.** Only on stack save/delete, rebuy/add-on, hand logged, and session end. Never on a timer.
   - Use `Text(date, style: .relative)` for "12m ago", so the view ticks by itself without updates.
   - Keep the data tiny (2 extra fields) [docs, 4 KB].
8. **Validation and number parsing.**
   - Locale decimal separators break `Double(text)` (e.g. "1,5"). Stay with `.numberPad` whole numbers like the rest of the app, and strip grouping separators before parsing.
   - Hard cap and soft warning as in §2.3. Stack 0 is valid (busted).
9. **Widget target build break.** `Session.swift` is compiled into the widget [code]. Forgetting to add the stack check model file to the widget's sources breaks the build. CI (`.github/workflows/ci.yml`, from PR #15) builds the app with its embedded widget and catches it.
10. **Charts performance and correctness.** Compute the chart series in the view model once per appear, not in the view body.
    - Dedupe identical timestamps.
    - Clamp the time range to the session's start and end (or now).
    - Session duration edits aren't possible today, so checks always fall inside the session. Keep it that way.
11. **Currency.** All new money text goes through `CurrencyFormatter` or `ComputedStats.formatCurrency` (still USD [code]). Never add `"$"` literals, so the future currency fix is one change.
12. **Abandon session.** `cashOut = 0` [code], so the chart ends at −invested even if the last check was positive. That's correct accounting; label the end point "Abandoned".
13. **Restore while a session is active.** With sync, a session can also be deleted from another device. Don't make it worse: the Live Activity controller must handle a missing session (shared with F1, pitfall 14).

---

# F3: Tips and add-ons: finish the money model (#27)

## 3.1 Problem and user story

The data model already has `addOns` and `tipRake`, the summary screen shows add-ons, and the README claims "Rebuy and add-on tracking". But users can't enter either one, can't edit them, and tips affect nothing [code]. Competitors (Poker Bankroll Tracker, Poker Analytics, Poler) let players record tips and costs and see their effect on hourly rate.

**User story:** "As a live player, I want to record add-ons and dealer tips during or after a session, fix them later, and see my results and hourly rate both after tips and before tips, so I know what tipping costs me."

## 3.2 Scope

In scope:
- Add-on entry during the session.
- Tip entry during the session and at the end.
- Editing add-ons and tips in session detail.
- Showing them in the end summary and session detail.
- "Before tips" profit and hourly rate.
- A lifetime "Tips" line on the Dashboard.
- Tests and README update.

Not in scope:
- Rake tracking. In cash games the house takes rake from pots, and players can't know their share.
- Multiple expense categories (hotel, food).
- Per-session "paid from pocket vs from chips" toggle (§3.4, option C).
- Tips in the Live Activity or home-screen widget.
- Fixing the currency setting.
- Tournament add-ons semantics (#8).

## 3.3 UX flow and copy

**During the session: Money sheet.** Turn the existing "Rebuy" button and sheet into **"Money"** (icon `dollarsign.circle`), so the 4-button action row keeps its width [code].
- Segmented control: **Rebuy | Add-on | Tip**.
- Field: "Amount" (`CurrencyField`, `.numberPad`).
- Primary button text follows the segment: **"Add Rebuy" / "Add Add-on" / "Add Tip"**.
- Footnote for Tip: "Tips you pushed from your chips. Your cash-out already reflects them."
- Footnote for Add-on: "Extra chips bought on top of your stack (top-up)."
- The segment remembers the last choice within the session (default Rebuy).
- Running total line in the sheet: "Tips so far: $15".
- Status bar: "Invested" includes add-ons (it already does via `totalInvested`). Tips don't show anywhere live except in this sheet.

**End session sheet**
- After "Cash Out Amount", add an optional **"Tips (optional)"** field, pre-filled with the session's running tip total.
- The preview has two lines:
  - "Net P/L: **+$300**"
  - "Before tips: +$325 · tips $25" (only if tips > 0)

**Session detail**
- Financial card: add **Add-Ons** (if > 0) and **Tips** (if > 0) tiles. The headline stays Net P/L.
- `$/hr` tile shows net. If tips > 0, add the caption "before tips $X/hr".
- Edit sheet: add **"Add-Ons $"** and **"Tips $"** fields under Rebuys. Footer: "Net P/L = cash-out − buy-in − rebuys − add-ons. Tips are shown separately."

**End summary** (`EndSessionSummaryView`)
- Rows: Add-Ons (already there, if > 0), **Tips** (if > 0), Net P/L.
- Then **"Before tips"** (if tips > 0), Hourly Rate, and **"Hourly before tips"** (if tips > 0).

**Dashboard financial summary**
- Keep Total P/L and Hourly Rate as net.
- If lifetime tips > 0, add the caption "**Tips: $340 · $4.10/hr**" under the 3 tiles.

**Labels.** Everywhere a number includes or excludes tips, label it: "Net" means after tips and is the default; "Before tips" is the only other variant. Never show an unlabeled second P/L, and avoid the word "gross".

**HIG notes**
- Segmented controls need short labels; 3 segments is fine.
- Number pad with an obvious primary action at the bottom.
- Secondary info in `.secondary` color and caption size.
- Check the action row at the largest Dynamic Type on the iPhone 16e.

## 3.4 Open question for the owner: what "tips" means (answer before the work starts)

**Option A (recommended, not decided): tips are already in the cash-out.**
- Live players tip from their chips, so the cash-out already went down by the tip amount.
- `netProfit` stays `cashOut − totalInvested`, **unchanged**.
- New: `profitBeforeTips = netProfit + tipRake` and `hourlyRateBeforeTips`.
- Effect on history: **none** for real users, since `tipRake` is 0 everywhere [code]. No restored backups change. The widget, Trends, mental-state correlation and #5's recorded values are all unchanged.

**Option B: tips come out of pocket.**
- `netProfit = cashOut − totalInvested − tipRake`. Only right for players who tip from their wallet.
- History shift: real sessions are still 0. **Demo/seeded data shifts by $5–25 per session**, which changes screenshots.
- Every `netProfit` consumer moves at once: Dashboard total and hourly, Trends (bankroll, day of week, histogram), mental-state correlation, the History list and totals, the widget total, hourly rate and streak (a +$10 session with a $15 tip becomes a loss and breaks a streak), `Session.roi`, and the inline ROI in `SessionDetailView`. It also double-counts for anyone who actually tips from chips.

**Option C: a per-session or global setting "Tips come from: chips / pocket".** Most accurate, but more UI and more tests. Defer.

Until the owner answers, the rest of this spec is written assuming **A**. If B is chosen, treat pitfalls 1–3 below as must-dos, and get #5 re-baselined.

## 3.5 Data model and migration

- **Database:** **no change.** `addOns: Double` and `tipRake: Double` already exist [code].
  - **Don't rename `tipRake`** to `tips`. That breaks the automatic upgrade unless you add `@Attribute(originalName:)`, which isn't worth it. Add a computed alias instead: `var tips: Double { get { tipRake } set { tipRake = newValue } }`. Mark it `@Transient` if the macro would otherwise try to store it [verify].
- **Computed properties on `Session` (option A):**
  ```swift
  var profitBeforeTips: Double { netProfit + tipRake }
  var hourlyRateBeforeTips: Double? {
      guard durationHours > 0.01 else { return nil }
      return profitBeforeTips / durationHours
  }
  ```
- **`ComputedStats`:** add `var totalTips: Double = 0` and `var hourlyRateBeforeTips: Double? = nil`.
  - Use **`var` with defaults** so the automatic initializer keeps working for the 7 existing `ComputedStats(...)` calls in `LeakFinderTests` [code]. A `let` with a default would be dropped from the initializer, and one without a default breaks those tests.
  - Fill them in `StatCalculator.computeAll`.
- **Backup format:** **no change, stays version 1.** `SessionDTO` already has `addOns` and `tipRake`, and `Session.fromDTO` restores them [code]. Add a round-trip test to lock this in.
- **Old backups:** restore unchanged. Under option A, values match exactly.

## 3.6 Code touchpoints

- `Models/Session.swift`: `tips` alias, `profitBeforeTips`, `hourlyRateBeforeTips`.
- `Models/ComputedStats.swift`: `totalTips` and `hourlyRateBeforeTips` (with defaults). `Services/StatCalculator.swift` `computeAll` fills them in.
- `ViewModels/ActiveSessionViewModel.swift`
  - `enum MoneyEntryKind { case rebuy, addOn, tip }`, `moneyKind`, `moneyAmountText`, `addMoney()`, which replaces or wraps `addRebuy()`.
  - `endSession(cashOut:tipRake:)` actually receives the tip amount.
  - `abandonSession` keeps any tips already entered.
  - Live Activity update after add-on (invested changes), not after tip.
- `Views/Session/ActiveSessionView.swift`: "Money" button, `rebuySheet` becomes `moneySheet` with a segmented `Picker`, plus the tip field and two-line preview in `endSessionSheet`.
- `Views/Session/EndSessionSummaryView.swift`: Tips, Before tips, and Hourly before tips rows.
- `Views/History/SessionDetailView.swift`: financial card tiles and caption. The inline ROI (line ~197) should use `session.roi` to avoid drift.
- `ViewModels/SessionDetailViewModel.swift`
  - `editAddOns`, `editTips`, and `beginEditing`/`saveEdits`.
  - Format existing values **without truncating** (`String(Int(x))` drops cents [code]). Use a helper that prints whole numbers as-is and keeps cents when present.
  - `saveEdits` should call `WidgetCenter.shared.reloadAllTimelines()`. It doesn't today [code].
- `Views/Dashboard/DashboardView.swift`: tips caption in `financialSummary`.
- `PokerStatsWidgets/PokerStatsLifetimeWidget.swift`: **no change** under A. Add a comment that the numbers are net.
- `Services/DataSeeder.swift`: keep `tipRake` 5–25 (good demo of the feature), and optionally seed add-ons on ~10% of sessions.
- `README.md`: update Session Management ("Rebuys, add-ons and tips"), and explain net vs before tips.
- `fastlane`: regenerate screenshots (Dashboard 01/02 will show the tips caption).
- Tests: `SessionTests`, `StatCalculatorTests`, new `MoneyEntryTests`, and a backup round-trip test (`BackupRoundTripTests`, new).

## 3.7 Acceptance criteria

1. The Money sheet adds rebuys, add-ons or tips. Rebuys and add-ons raise "Invested"; tips don't. The Live Activity's invested amount includes add-ons.
2. The end sheet's tip field is pre-filled with the running total and editable. The saved session has the entered `tipRake`.
3. Net P/L = cash-out − buy-in − rebuys − add-ons (**unchanged under A**). Before tips = Net + tips. The hourly versions are consistent.
4. Session detail shows Add-Ons and Tips when > 0, and the edit sheet changes both. Saving updates all screens, and the home-screen widget refreshes.
5. The Dashboard tips caption appears only when lifetime tips > 0, with the correct totals.
6. Every screen with a second P/L or hourly number labels it "Before tips". The default numbers are net.
7. A session with stored cents (e.g. 2.50) keeps them after opening and saving the edit sheet without changes.
8. Existing totals for a real user are the same before and after the update (option A). Check with the #5 checklist values.
9. A backup round trip (version 1) keeps `addOns` and `tipRake`.
10. CI is green, including the updated `SessionTests` and `LeakFinderTests` compiling unchanged.

## 3.8 Test plan

**Unit tests**
- `SessionTests`
  - `netProfit_ignoresTips` (A)
  - `profitBeforeTips_addsTips`
  - `hourlyRateBeforeTips`
  - `totalInvested_includesAddOns` (exists)
  - `tipsAlias_readsWritesTipRake`
- `StatCalculatorTests`: `computeAll_totalTips`, `computeAll_hourlyBeforeTips`, and existing totals unchanged when tips > 0.
- `MoneyEntryTests` (view model with in-memory container)
  - Rebuy, add-on and tip go to the right fields
  - Invalid amount is a no-op
  - `endSession` stores tips
  - `abandonSession` keeps tips
  - Edit save keeps cents and treats empty as unchanged
- Backup round trip: `toDTO`/`fromDTO` with `addOns` and `tipRake` set.

**Manual end-to-end**
1. Start a session at 200. Add a rebuy of 200, an add-on of 100, and tips of 5 and 10. Invested is 500. End with cash-out 650 and tips 15 pre-filled: Net +$150, Before tips +$165, hourly values match.
2. Edit: change tips to 20 and add-ons to 0. Summary, detail, Dashboard, History and widget all update consistently.
3. Seed demo data (DEBUG): the Dashboard shows the tips caption, and the Net totals equal what the old formula gives for the same data. The seeder is random, so check this in a unit test or with a fixed seed.
4. Run `fastlane snapshot` and review the screenshots.
5. Sign in, back up, delete the app, reinstall, restore: add-ons and tips are restored.

**Effort: Small, 2–3 dev-days plus ~1 QA day** (option A). Add ~1 day under option B for re-baselining and widget/Trends/streak checks.

## 3.9 Pitfalls and mitigations

1. **The `netProfit` definition shifting history** (only under B).
   - Under A it doesn't move.
   - Under B: re-baseline #5's recorded values, and re-check streaks in `PokerStatsLifetimeWidget` (`netProfit > 0`), the Trends bankroll chart, day-of-week, histogram buckets, and mental-state correlation (uses `session.hourlyRate`).
   - Note in release notes that past demo totals change.
2. **The widget.** It computes totals and streak itself from `netProfit` [code], so it follows whatever `netProfit` means.
   - Under A no change. Don't add "before tips" to the widget (no room, and it creates ambiguity).
   - Reload the widget after edits: `deleteSession` reloads, but `saveEdits` doesn't [code]. Fix it.
3. **Leak Finder and hourly rate.** Leak Finder doesn't use money [code], so no change. Hourly rate stays net everywhere it's used today. Keep the mental-state insight ("calm vs tilted $/hr") on net; never mix in before-tips numbers.
4. **Currency setting ignored.** All new labels go through `CurrencyFormatter` (USD). Don't add `"$"` literals in new views (the existing `CurrencyField` prefix is acceptable for now). Track the currency fix separately, as one central change later.
5. **Demo data and screenshots.** The seeder already puts 5–25 in tips on every seeded session [code], so the new tips UI will suddenly show in demo builds and App Store screenshots.
   - Decide to keep it (recommended: shows the feature) and regenerate screenshots via fastlane.
   - Under option B, demo totals also drop.
6. **Making it clear which numbers include tips.**
   - Net is the default and is never labeled differently.
   - "Before tips" always carries that label and only appears when tips > 0.
   - Put the explanation in the edit sheet footer and the Money sheet footnote.
7. **Renaming the stored property.** Don't rename `tipRake` (or `addOns`). Use computed aliases only.
8. **Edit sheet truncation.** `String(Int(session.buyIn))` drops cents [code]. Fix it for the new fields and the existing ones in the same change, and test the round trip with cents.
9. **Add-ons vs tournaments (#8).** Add-ons in cash games mean "top-up". When #8 lands, tournament add-ons may need their own field or meaning. Keep the label "Add-on" with the "(top-up)" footnote, and leave a TODO linking #8.
10. **Abandon with tips.** `abandonSession` sets cash-out to 0 [code]. Keep entered tips so the P/L stays consistent; "Before tips" then equals −invested + tips.
11. **Action row space.** Renaming "Rebuy" to "Money" keeps 4 buttons. Check the iPhone 16e at the largest Dynamic Type.

---

## 4. Sequencing, dependencies, and estimate

### 4.1 Dependencies

| Item | F3 (#27) | F1 (#29, #28) | F2 (#30) |
|---|---|---|---|
| **CI green** (done: PR #15 fixed the `AppGroupContainer` force-unwrap) | Should be green so the new tests run | **Hard**: F1 adds `AppGroupContainer.shared` and must keep the merged App Group handling | **Hard**: catches the widget-target build break |
| **#1 Sign in with Apple config** | None | None | Needed for the two-device sync tests |
| **#4 / #5 backup and restore end-to-end** | Run #5 on a fixed build. Option A doesn't change the recorded values; option B needs #5 re-baselined, so do F3-B after #5 | None | **None.** F2 no longer touches the backup format |
| **1.1 Sync** (`docs/specs/1.1-sync.md`, Max's technical design) | None | None (Lock Screen folds sync as ordinary hands once sync exists) | **Hard**: stack checks are a synced record type |
| **F1 merged** | None | n/a | **Hard**: both reshape the Live Activity |

### 4.2 Recommended order

1. **Finish the 1.0 work first:** sign-in, restore and account deletion end-to-end. None of these 3 features should jump ahead of that.
2. **F3, tips and add-ons (Small).** No database or backup change, quick win, makes the README true. Can start once CI is green. If option B is chosen, start after #5 is signed off.
3. **F1, Lock Screen fold (Medium).** Does the shared foundations (`AppGroupContainer.shared`, `HandLoggingService`, `LiveActivityController`, `sessionID` on the Live Activity, `scenePhase` re-sync, stable view model) that F2 reuses. Start with the 0.5-day spike (#28, section 4.5).
4. **F2, stack checks (Medium).** Last: it needs the 1.1 sync layer and builds on F1's Live Activity controller and data struct.

**Parallelism:** with two iOS devs, F3 and F1 can run in parallel. Expect merge conflicts in `ActiveSessionView` and `ActiveSessionViewModel`: merge F3 first. F1 and F2 shouldn't run in parallel, since both reshape `SessionActivityAttributes.ContentState` and `PokerStatsLiveActivity`. If they must, agree the full `ContentState` up front: all optional fields `nextHandNumber, quickFoldPosition, undoHandID, undoHandNumber, undoPosition, livePL, livePLAsOf`.

### 4.3 Estimate (one iOS dev, plus QA)

| Feature | Dev | QA (device) | Calendar (1 dev) |
|---|---|---|---|
| F3 | 2-3 days (+1 if option B) | ~1 day | ~1 week including review |
| F1 | 5-7 days (incl. 0.5-day spike) | ~2 days | ~1.5-2 weeks |
| F2 | 5-6 days (after 1.1 sync exists) | ~1.5 days | ~1.5 weeks |
| **Total** | **12-16 dev-days** | **~4.5 days** | **~4-5 weeks sequential**, ~3 weeks with 2 devs (F3 and F1 in parallel, then F2) |

Not included: the 1.1 sync work itself, App Store review time, waiting on the owner's answers, and any fixes from 1.0 end-to-end testing.

### 4.4 Open questions for the owner (needs-owner)

None of these is decided. The recommendations are suggestions only.

1. F3 (#27): what do tips mean: A (recommended), B or C (section 3.4)?
2. F2 (#30): should the Lock Screen live P/L default to **on** or **off**, given privacy at the table (section 2.8, pitfall 6)?
3. F2 (#30): should the chart show **P/L over time** (recommended), raw stack, or both via a picker?
4. F1 (#29): is `.alwaysAllowed` (no Face ID) OK for Fold and Undo, with the Settings toggle as the safety valve?
5. F2 (#30): with stack checks syncing, should the "Show live P/L on Lock Screen" toggle stay per device (as proposed), or sync per account?

### 4.5 Things a dev must verify early (spike, ~0.5 day, start of F1)

- `LiveActivityIntent` runs in the app process when the app has been force-quit, and how long it may run. Check what happens before the first unlock after a reboot.
- Lock Screen and expanded Dynamic Island buttons fire with `.alwaysAllowed` without unlocking. Buttons aren't available in compact or minimal views.
- An activity started by the old build decodes with the new optional fields (update the app mid-session).
- Behavior of rapid local `Activity.update` calls (merged or delayed?).
- Whether `.privacySensitive()` redacts Live Activity content when locked (for F2's toggle default).
- The database's automatic upgrade handles F2's new local storage for stack checks (cheap to check in the same spike once the 1.1 sync design picks the form).

## 5. Sources

- Apple, LiveActivityIntent: https://developer.apple.com/documentation/appintents/liveactivityintent
- Apple, Adding interactivity to widgets and Live Activities: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- Apple, Displaying live data with Live Activities (8-hour limit, 4 KB): https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Apple, IntentAuthenticationPolicy: https://developer.apple.com/documentation/appintents/intentauthenticationpolicy
- Apple Developer Forums, SwiftData changes from a Live Activity button not visible in the app: https://developer.apple.com/forums/thread/764290
- Poker Analytics 6.7 (stack tracking): https://www.poker-analytics.net/blog/2025/12/poker-analytics-6-7/
- Poker Analytics 6 release notes (tips / transaction filters): https://www.poker-analytics.net/blog/2022/01/poker-analytics-6-release-note/
- Poker Bankroll Tracker (tips/costs; stack-tracking review): https://pokerbankrolltracker.net/ and https://apps.apple.com/us/app/poker-bankroll-tracker/id999514771
- PokerRoll comparison (Poker Stack "stack checks", Poler expenses): https://pokerroll.app/en/blog/best-poker-bankroll-tracker
