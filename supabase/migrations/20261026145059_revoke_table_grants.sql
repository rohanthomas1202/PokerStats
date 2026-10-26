-- #244: take TRUNCATE, TRIGGER and REFERENCES away from the API roles.
--
-- Supabase's default privileges gave anon and authenticated ALL on the
-- tables in 20260420000000_init_schema.sql. TRUNCATE skips RLS, so a role
-- holding it could empty a table no matter whose rows are in it. PostgREST
-- can't issue TRUNCATE, TRIGGER or REFERENCES, so nothing reaches this today;
-- this is defense in depth. Select, insert, update and delete stay, and RLS
-- keeps users apart on them.

revoke truncate, trigger, references on public.profiles from anon, authenticated;
revoke truncate, trigger, references on public.backup_metadata from anon, authenticated;

-- Tables that postgres creates in public later (every migration runs as
-- postgres) start without these three as well. This changes only postgres's
-- default privileges in public; tables still get select, insert, update and
-- delete by default, and docs/design/1.1-sync.md section 3.5 still revokes
-- per table on top of this.
alter default privileges for role postgres in schema public
    revoke truncate, trigger, references on tables from anon, authenticated;

-- handle_new_user only runs as the on_auth_user_created trigger. Postgres
-- checks EXECUTE on a trigger function when the trigger is created, not when
-- it fires, so signup keeps creating profile rows without these grants.
-- public too: Postgres grants EXECUTE to public on every new function.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
