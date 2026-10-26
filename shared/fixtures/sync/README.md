# Sync API contract

The push and pull messages from `docs/design/1.1-sync.md` (sections 2, 4.1, 4.3, 9.4 and 9.6) as JSON Schema (draft 2020-12), with examples. This contract is the source of truth for the server (#84) and the iOS client (#85). A protocol change updates the design doc and these files in the same PR.

| Path | What |
|---|---|
| `schema/push-request.schema.json` | Body of `rpc/sync_push`. `$defs/change` is the one definition of a queued change. |
| `schema/push-response.schema.json` | Its return value: `ok` with per-change results, or `upgrade_required`, `wiped`, `account_missing`, `invalid`. |
| `schema/pull-*.schema.json` | One PostgREST page of `poker_sessions`, `hands`, `user_settings` (with sync columns), and the `sync_state` read in pull step 1. |
| `schema/common.schema.json` | Column types shared by pushes and pulls. |
| `columns.json` | Client columns per table (the only keys allowed in `fields`), create-only columns, and the Swift-to-column map from 9.4. |
| `examples/<schema>/valid/`, `examples/<schema>/invalid/` | Synthetic payloads. Each invalid file is named for the rule it breaks, and `examples/expected-errors.json` gives the error it must fail with. |
| `contract.test.ts` | Validates every example, and checks `columns.json` against the schema and against sections 2 and 9.4 of the design doc. |

Run: `cd shared/fixtures/sync && deno test --frozen --allow-read=.,../../../docs`. CI runs it in the "Sync contract" job when `shared/`, `supabase/` or `.github/` changes. The validator is Ajv 8.20.0, pinned in `deno.json` and `deno.lock`.

## Unknown properties

- **Client to server is closed.** The push envelope, each change and each `fields` object reject unknown keys (`additionalProperties` / `unevaluatedProperties: false`). The server is always the newest party (design 2.4), so it knows every key a client may send, and 4.1 already rejects unknown keys in `fields`. A typo such as `faced3_bet` fails here instead of reaching the server.
- **Server to client is open.** Push responses and pulled rows allow keys the schema doesn't list, and clients ignore them. A later migration adds columns that `select *` returns to older apps, which must keep working (design 5.1).
- **Protocol words are closed, data values are open.** `op`, `table`, `status` and `result` are enums; a new value is a protocol change. Data enums (`game_type`, `status` on a session, `position`, ...) are plain strings, as the columns have no check (2.4) and clients decode unknown values with fallbacks (9.5).

Adding a field to every change (for example a device edit time, if the owner picks it for owner question 1 on #84) is one line under `$defs/change/properties` in `push-request.schema.json`, plus examples.

## Limits

In the schema: at most 500 changes per push; `notes` 10,000 characters; `location`, `stakes`, `default_stakes` 200; `currency` 8; mental levels 1 to 5; money within `numeric(14,2)`; `seq` at least 1.

Server-enforced only (the schema can't express them):

| Rule | Server result |
|---|---|
| Payload at most 1 MB | `invalid` |
| `table_config` at most 16 KB (`pg_column_size`) | `rejected` |
| Rows per user (optional): 50,000 sessions, 500,000 hands | `rejected`, reason `row_cap` |
| `hand_number` resent with a different value | `rejected` with the trigger's SQLSTATE |
| `seq` strictly increasing per device (4.4); a `seq` at or below `last_applied_seq` | `skipped` |
| Foreign keys, not-null on insert, other column checks | `rejected` with the SQLSTATE |

The schema describes what a conforming client sends. The server is more lenient in one place: an unknown `table` or a disallowed key in `fields` rejects that change only (`rejected`), not the batch.

## Decisions where the design doc is not explicit

1. **`seq` starts at 1.** `devices.last_applied_seq` defaults to 0 and `seq <= last_applied_seq` is skipped, so a change with `seq` 0 would never apply. With `nextSeq` 0 on a new `deviceId`, the first change gets 1.
2. **`id` is not a key in `fields`.** The change's `id` carries it. `deleted_at` is set only by the `delete` and `restore` ops, so it is not in `fields` either.
3. **`hand_number` in `fields` means a create.** It is sent only on create (9.4), and a create carries every not-null hand column without a default, so `fields` with `hand_number` must also have `session_id`, `played_at`, `preflop_action`, `faced_3bet` and `position`. A full-row resend with the same number stays valid (7.1).
4. **`user_settings` changes carry the account's user ID as `id`.** The table is keyed on `user_id` and the local `Settings.id` is not synced (2.6), but every change has an `id`. The server ignores it and uses `auth.uid()`. To confirm with #85.
5. **`user_settings` columns are not null in pulled rows.** 2.6 doesn't say; the Swift `Settings` properties are all non-optional. #84's migration must match, or this changes.
6. **`first_sync_done` is required**, as in the 4.1 example. Send `false` when not finishing the first sync.
7. **Timestamps** need an explicit offset. 9.4 asks clients for UTC with fractional seconds; the 4.1 example has none, so fractional seconds are optional. Pulled rows come back as `+00:00`.
8. **Non-ok push responses carry only `status`.** On `wiped`, the client reads the new epoch from `sync_state` in the pull (4.3, 6.1).
9. **`rejected` needs a `reason`**: a SQLSTATE (`23503`) or a lowercase server code. The design names `unknown_table` and `row_cap`; it doesn't name the code for a disallowed key in `fields`, which #84 picks.
