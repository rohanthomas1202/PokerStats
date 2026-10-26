# Stat definitions and golden fixtures

What the iOS app computes today for every stat it shows, as data that the web dashboard and the sync tests can check against. Rows use the column names of `docs/design/1.1-sync.md` section 2, so a dataset row has the shape of a pulled row. All data is synthetic. Changing a stat is out of scope here: if the app's behavior changes, this folder changes in the same PR.

| Path | What |
|---|---|
| `definitions.json` | One entry per stat: the expected field paths it covers, inputs, formula, when it is null, display rule and the Swift source lines. Also the Leak Finder ranges and the display rules. |
| `datasets/*.json` | Input `sessions` and `hands` rows plus `now`, `time_zone` and the `expected` output. |
| `display.json` | Displayed strings for given values (en_US), including rounding ties. |
| `reference.ts` | A TypeScript port of the Swift, each function citing the code it ports. |
| `stats.test.ts` | The check. |
| `update.ts` | Rewrites the expected values from `reference.ts`. |

Run: `cd shared/fixtures/stats && deno test --frozen --allow-read=.,../sync`. CI runs it in the "Shared fixtures" job when `shared/`, `supabase/` or `.github/` changes. The test checks that:

- every session and hand row passes the pull schemas in `../sync/schema`,
- each dataset's `expected` equals `reference.ts` output, numbers within a relative 1e-9,
- the fields of `expected` and the paths in `definitions.json` are the same set, and every stat has inputs, formula, display and source,
- the Leak Finder ranges in `definitions.json` equal the ones in `reference.ts`,
- every `display.json` string matches its display rule,
- the edge cases below are still present.

## How the expected values were produced

`reference.ts` was written by reading the Swift listed below and porting it function by function, keeping the app's filters, guards, thresholds and order of operations. `update.ts` ran it over each dataset's inputs. The core lifetime numbers were then counted by hand from the hand list (26 live hands, VPIP 16/26, PFR 11/26, fold to 3-bet 2/4, c-bet 5/8, WTSD 6/13, W$SD 4/6, total -280 over 8 hours), along with the weekdays in America/Chicago, the histogram buckets, the streak and the mental insight.

No Swift has been run against these files yet: the app's models use SwiftData, which does not build on Linux. The iOS-side test that loads the datasets into the app's models and compares `StatCalculator`, `TrendCalculator`, `LeakFinder` and the widget against `expected` is #238. Adding these fixtures (#235) leaves
#238 open. Until it lands, a disagreement between this folder and the app is a
bug here, unless the app changed.

Sources ported (read-only): `PokerStats/Services/StatCalculator.swift`, `TrendCalculator.swift`, `LeakFinder.swift`; `PokerStats/Models/Session.swift`, `Hand.swift`, `Enums.swift`, `ComputedStats.swift`; `PokerStats/Utilities/CurrencyFormatter.swift`; `PokerStats/ViewModels/DashboardViewModel.swift`, `TrendsViewModel.swift`, `LeakFinderViewModel.swift`; `PokerStats/Views/Components/PlayStyleLabel.swift`, `PokerStats/Views/History/SessionDetailView.swift`; `PokerStatsWidgets/PokerStatsLifetimeWidget.swift`.

## Rules the datasets pin down

- **Tombstones.** Rows with `deleted_at`, and hands of a tombstoned session, are not inputs (design 9.1). The app hard-deletes today, so this is the 1.1 rule rather than current behavior.
- **Money stats** count only `status = 'completed'`. An unknown status decodes as active (`Session.swift:17`) and is left out.
- **Abandoned** sessions are stored as completed with `cash_out = 0` (`ActiveSessionViewModel.swift:147-156`): a full loss, and their hours count.
- **Net profit** is `cash_out - (buy_in + rebuys + add_ons)`. `tip_rake` is not subtracted.
- **Duration** of a session with no `end_time` runs to `now`. Hourly rates need more than 0.01 hours (36 s), so a zero-length session has no hourly rate.
- **Hand stats** use every live hand, whatever its session's status.
- **Time.** `now` and `time_zone` are dataset inputs. Weekdays use `time_zone` (the app uses the device's). The 30-day window keeps rows at or after `now` minus 30 days.
- **Display.** Percent and currency round half to even, as printf and NumberFormatter do. JavaScript's `toFixed` rounds ties up (`(6.25).toFixed(1)` is `6.3`, the app shows `6.2%`), so the web must not use it for these.

Edge cases present (the test fails if one disappears): no rows, a tombstoned session with hands, a tombstoned hand in a live session, an active session, an unknown status (`paused`), an abandoned session, a zero-length session, custom stakes, a nonzero `tip_rake`, a session shorter than the 0.01-hour hourly guard, hands at the unknown position `?`, a session with 10+ hands (session Leak Finder), 20+ hands (lifetime Leak Finder and rolling stats), a P/L on the top histogram edge, a session outside the 30-day window, and a session whose weekday differs between UTC and America/Chicago.

## App and doc disagreements

The fixtures encode the app as of #246. The decisions on these points are in Intended behavior below. A change lands in the app and here together.

1. **Unknown status.** The app treats it as active, so it is left out of money stats. Design 9.5 says an unknown status decodes as completed, which would count it.
2. **Abandoned sessions** are stored as completed, so under spec section 12 ("only completed sessions count toward money stats") they count as a full loss of the buy-in, with their hours. Confirm that is intended.
3. **tip_rake** is not part of net profit.
4. **Hand scope.** Lifetime hand stats include hands of active and unknown-status sessions. The app also counts hands with no session, which are never synced (design 7.1), so a web total could be lower than the app's for the same account. The datasets have no orphan hands.
5. **Fold to 3-bet** counts every hand with `faced_3bet`, not only hands where hero raised first, as the code comment says.
6. **P/L histogram.** A session whose profit is a multiple of 100 and is the maximum falls outside every bucket. When every profit is in one bucket width (for example a single +100 session), the app shows one bucket labelled `$0` with lower bound 0. Both look like bugs; the fixtures record what the app shows.
7. **Time zone.** Weekday grouping and the 30-day cutoff use the device's calendar and zone, so the same account can chart differently on two devices or on the web. The app subtracts 30 calendar days; the fixtures subtract 30 x 24 hours and avoid a DST change.
8. **Widget money** truncates toward zero, with `+` for zero and `-$0` for a loss under $1, and the widget's hourly rate is whole dollars. The app rounds half to even and shows hourly to the cent.
9. **ROI** exists per session only (shown when completed with an invested amount above 0). Spec section 12 lists ROI with no lifetime definition.
10. **Mental insight** takes the first tilt level of 4 or higher, so level 5 is ignored when level 4 has data.
11. **Ties.** The cumulative bankroll sorts sessions by start time and rolling VPIP/PFR sorts hands by time; equal timestamps have no defined order. Leak Finder's list order within one rating is also unstable, so the datasets store ratings by stat rather than as a list. The datasets avoid equal timestamps.
12. **Completed with no end_time** gets a duration up to now. Pulled rows could carry this; the app never writes it.
13. **Display locale.** NumberFormatter follows the device locale; `display.json` assumes en_US.
14. **Percent display** rounds the binary value half to even; a web port has to match on ties (see Display above).

## Intended behavior

The team's decisions on the points raised in #246 (point numbers from the #246 PR body), from the iOS triage on #246 and Sam's decisions on #84 and #247. The iOS app (#85) and the 1.2 web port follow these and shouldn't reopen them.

- **Abandoned sessions (2).** An abandoned session is a completed session with `cash_out` 0, counted as a loss with its hours. `abandonSession` has no callers today.
- **tip_rake (3).** Not subtracted from net profit. The definition waits on the owner's answer on #27, section 3.4.
- **Hand scope (4).** Hand stats use every live hand, including hands of active sessions. Hands with no session can't come from the UI; #85 may drop them from stat inputs. No fixture change.
- **Time zone and the 30-day window (7).** The app uses the device zone and subtracts 30 calendar days; the web uses the browser zone and calendar-day subtraction. The fixtures stay pinned to America/Chicago with no DST crossing.
- **Ties (11).** The datasets avoid equal timestamps. If a port needs a deterministic order, sort on (time, id) on both sides (#238).
- **Locale (13).** `display.json` is en_US; the app follows the device locale.
- **Rounding (14).** Percent and currency round half to even. The web must not use JavaScript's `toFixed`.
- **Tombstones (15).** Excluding `deleted_at` rows is the 1.1 rule (design 9.1). The app hard-deletes today; #85 implements tombstones.

### Pending changes

These will move expected values. Each fix updates `reference.ts`, regenerates the expected values with `update.ts`, and #238 checks the Swift against them.

- Unknown status counts as completed (1), and a completed session with no `end_time` ends at its start time (12): #236.
- Fold to 3-bet counts only hands where hero raised preflop (5): #253.
- The P/L histogram's last bucket includes the maximum, and the `$0` special case goes away (6): #248.
- Widget money rounds half to even instead of truncating (8): #249.
- Mental insight pools tilt levels 4 and 5 (10): #250.
- Lifetime ROI is the owner's call (9): #252.
