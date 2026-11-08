# Local export format 1

`dataset.json` is a synthetic input, with two completed sessions (including an
abandoned session with zero cash-out), an active session, and one hand in each.
Its CAD amounts are exact cents so the app's unrounded stats and export totals
can be compared directly. Notes exercise commas, quotes, LF, and non-ASCII text.
Swift tests separately cover CR, sync cents rounding/clamping, and offset dates.

Expected files: `sessions.csv`, `hands.csv`, `pokerstats-export.json`.
Regenerate independently with `python3 shared/fixtures/export/update.py` from the
repository root. Tests compare bytes; they never regenerate expected output.
There is no Deno test or workflow change for these fixtures.

## Contract

All files are UTF-8, no BOM, with LF separators and a final LF. Rows are sorted
by UUID string ascending, regardless of fetch order. UUIDs are uppercase. Dates
use SyncCoding's ISO 8601 UTC strings with milliseconds. Money uses SyncCoding's
cents rounding/clamping, in currency units, not integer cents. CSV money is
plain decimal (no symbols, grouping, or exponent); trailing zeroes are optional.
CSV fields use RFC 4180 escaping, with LF rather than CRLF record separators.
Nulls are JSON null and empty CSV cells; empty strings remain empty strings in
JSON. A missing table config is null; present table config is an object in JSON
and a compact sorted-key JSON string in CSV. Invalid config bytes fail the
export rather than silently dropping the data. A hand without a session fails
rather than silently omitting the hand. Inputs are live local rows, with no
invented tombstones or server metadata.

JSON is a compact, sorted-key object with `format_version: 1`, `sessions`, and
`hands`. Each array row has the same fields as its corresponding CSV:

- Sessions: `id,start_time,end_time,location,stakes,notes,game_type,status,buy_in,rebuys,add_ons,cash_out,tip_rake,tilt_level,energy_level,focus_level,table_config,currency`
- Hands: `id,session_id,hand_number,played_at,preflop_action,faced_3bet,three_bet_response,postflop_result,did_cbet,notes,position`

`currency` comes from Settings and is repeated per session in both formats.
All other keys reuse the sync column names and full-row model mapping. There
are no user_id, revision, deleted_at, purged_at, server_updated_at,
updated_by_device, or logging_device_id columns.

Empty inputs yield header-only CSVs and JSON with two empty arrays. Exporting
includes active sessions and their hands, but stats parity follows
`shared/fixtures/stats/definitions.json`: only completed sessions count toward
session count and profit; all hands count. Profit is cash-out minus buy-in,
rebuys, and add-ons. Tip/rake is not subtracted again. Swift tests load these
rows into an in-memory ModelContainer and compare both formats to the actual
DashboardViewModel/StatCalculator output, plus every money column per session.
