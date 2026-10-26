-- Table and function privileges for anon and authenticated, pinned to what
-- supabase/migrations/ leaves today: Supabase's default privileges minus the
-- revokes in 20261026145059_revoke_table_grants.sql (#244). RLS is what keeps
-- users apart on these tables. A migration that changes a grant must update
-- this file in the same PR, so every grant change is visible in review. New
-- tables follow docs/design/1.1-sync.md section 3.5 and get their own
-- expected lists here.
begin;
select plan(20);

-- No TRUNCATE (it skips RLS), TRIGGER or REFERENCES for either role (#244).
select table_privs_are('public', 'profiles', 'anon',
  array['DELETE', 'INSERT', 'SELECT', 'UPDATE'],
  'anon privileges on profiles');
select table_privs_are('public', 'profiles', 'authenticated',
  array['DELETE', 'INSERT', 'SELECT', 'UPDATE'],
  'authenticated privileges on profiles');
select table_privs_are('public', 'backup_metadata', 'anon',
  array['DELETE', 'INSERT', 'SELECT', 'UPDATE'],
  'anon privileges on backup_metadata');
select table_privs_are('public', 'backup_metadata', 'authenticated',
  array['DELETE', 'INSERT', 'SELECT', 'UPDATE'],
  'authenticated privileges on backup_metadata');

-- The same, spelled with has_table_privilege for the privileges that matter
-- most: both roles can reach the rows, so RLS must hold, and neither can
-- truncate past it.
select ok(has_table_privilege('anon', 'public.profiles', 'select'), 'anon can select profiles (RLS filters)');
select ok(has_table_privilege('authenticated', 'public.backup_metadata', 'insert'), 'authenticated can insert backup_metadata (RLS checks)');
select ok(not has_table_privilege('anon', 'public.profiles', 'truncate'), 'anon cannot truncate profiles');
select ok(not has_table_privilege('authenticated', 'public.backup_metadata', 'truncate'), 'authenticated cannot truncate backup_metadata');

-- A table postgres creates in public later starts without the three either
-- (the alter default privileges in the #244 migration). Dropped right away,
-- and the whole file rolls back.
create table public.grants_test_probe (id int);
select table_privs_are('public', 'grants_test_probe', 'anon',
  array['DELETE', 'INSERT', 'SELECT', 'UPDATE'],
  'anon default privileges on a new public table');
select table_privs_are('public', 'grants_test_probe', 'authenticated',
  array['DELETE', 'INSERT', 'SELECT', 'UPDATE'],
  'authenticated default privileges on a new public table');
drop table public.grants_test_probe;

-- handle_new_user is trigger-only and security definer: no one calls it
-- directly (#244).
select function_privs_are('public', 'handle_new_user', array[]::text[], 'anon', array[]::text[],
  'anon has no execute on handle_new_user');
select function_privs_are('public', 'handle_new_user', array[]::text[], 'authenticated', array[]::text[],
  'authenticated has no execute on handle_new_user');
select is_empty(
  $$select 1 from pg_proc p,
      aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
    where p.oid = 'public.handle_new_user()'::regprocedure
      and a.grantee = 0 and a.privilege_type = 'EXECUTE'$$,
  'public has no execute on handle_new_user'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.handle_new_user()'::regprocedure),
  true,
  'handle_new_user is security definer'
);

-- Signup still creates the profile. pg_prove runs as postgres, which owns
-- handle_new_user and can't switch to supabase_auth_admin (the Auth server's
-- role), so drop execute from postgres and from service_role (which postgres
-- is a member of) too, for this transaction only. postgres then can't execute
-- the function through any role, and the trigger still fires.
revoke execute on function public.handle_new_user() from postgres, service_role;
select ok(not has_function_privilege('postgres', 'public.handle_new_user()', 'execute'),
  'postgres has no execute on handle_new_user in this transaction');
insert into auth.users (id, email) values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'd@example.invalid');
select results_eq(
  $$select count(*)::int from public.profiles where id = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'$$,
  array[1],
  'signup creates a profile with no execute on handle_new_user'
);

-- Every table in public has RLS on. This guards every table a later
-- migration adds.
select is_empty(
  $$select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity$$,
  'every table in public has RLS enabled'
);
select tables_are('public', array['profiles', 'backup_metadata'],
  'public has exactly the tables this file pins');

-- Realtime is not used (design 4.6): no public table is published.
select is_empty(
  $$select tablename from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public'$$,
  'no public table is in the supabase_realtime publication'
);

-- No other table in public lets anon or authenticated truncate.
select is_empty(
  $$select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p')
      and (has_table_privilege('anon', c.oid, 'truncate')
        or has_table_privilege('authenticated', c.oid, 'truncate'))$$,
  'no table in public is truncatable by anon or authenticated'
);

select * from finish();
rollback;
