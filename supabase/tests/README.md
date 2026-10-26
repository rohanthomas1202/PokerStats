# Database tests

pgTAP tests for the schema in `supabase/migrations/`, run by `supabase test db` against a local database. They never touch the live project.

| Folder | What |
|---|---|
| `database/` | One file per table or concern. Each file wraps itself in `begin` ... `rollback`, so it leaves nothing behind. |
| `committed/` | Tests that need committed transactions on one connection, such as the pooled-connection test in docs/design/1.1-sync.md section 3.2. They don't use `begin`/`rollback`. |

## Run locally

Needs Docker and the Supabase CLI version that CI pins (`SUPABASE_CLI_VERSION` in `.github/workflows/ci.yml`).

```sh
supabase start -x gotrue,realtime,storage-api,imgproxy,kong,mailpit,postgrest,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
supabase test db
supabase db reset --local   # after editing a migration, rebuild from supabase/migrations/
supabase stop --no-backup
```

Only Postgres starts. The tests are SQL, so they don't need Auth, Storage or PostgREST. Never pass `--linked` or `--db-url`.

## How a test acts as a user

Insert users straight into `auth.users`, then switch role and JWT claims for the current transaction, the way PostgREST does:

```sql
insert into auth.users (id, email) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b@example.invalid');
set local role authenticated;
set local request.jwt.claims = '{"sub": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "role": "authenticated"}';
-- ... queries run as B; auth.uid() returns B ...
set local role anon;
set local request.jwt.claims = '{"role": "anon"}';
reset role;   -- back to the table owner to check what changed
```

Storage needs one more setting: the Storage API sets `storage.allow_delete_query = 'true'` before a delete, and without it a trigger refuses every direct delete on `storage.objects` before any policy runs.

## Adding a table

Every new table gets a file in `database/` in the same PR as its migration. Use `profiles_rls.test.sql` as the template:

1. RLS is enabled.
2. As B: select returns only B's rows, and nothing by A's `id`.
3. As B: update and delete aimed at A's rows change nothing, which you check afterwards as the owner; B's own update and delete work where a policy allows them.
4. As B: an insert or update that would give a row to A raises `42501`.
5. As anon: nothing is visible, and writes raise or change nothing.
6. `policies_are` lists exactly the table's policies.

Then add the table's expected privileges for `anon` and `authenticated` to `database/grants.test.sql`, and add it to its `tables_are` list. That file fails on any grant change and on any table in `public` without RLS.

## Committed tests

`supabase test db` runs every `.sql` file under this folder through `pg_prove`, one `psql` session per file, and adds no transaction of its own. A file opts out of the rollback by leaving out `begin`/`rollback`: each statement then commits, and the connection stays the same for the whole file. Such a file must:

- live in `committed/`, so reviewers know it commits;
- delete every row it creates, including after a failed assertion where it can, because nothing rolls it back;
- not depend on rows from other files, which run in name order.
