-- Table and function privileges for anon and authenticated, pinned to what
-- 20260420000000_init_schema.sql leaves today (Supabase's default privileges;
-- the init schema revokes nothing). RLS is what keeps users apart on these
-- tables. A migration that changes a grant must update this file in the same
-- PR, so every grant change is visible in review. New tables follow
-- docs/design/1.1-sync.md section 3.5 and get their own expected lists here.
-- Known gap: TRUNCATE (which bypasses RLS), TRIGGER and REFERENCES are
-- granted too. PostgREST can't issue them; a later migration revokes them
-- and updates this file (PR #243 finding 1).
begin;
select plan(12);

select table_privs_are('public', 'profiles', 'anon',
  array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE'],
  'anon privileges on profiles');
select table_privs_are('public', 'profiles', 'authenticated',
  array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE'],
  'authenticated privileges on profiles');
select table_privs_are('public', 'backup_metadata', 'anon',
  array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE'],
  'anon privileges on backup_metadata');
select table_privs_are('public', 'backup_metadata', 'authenticated',
  array['DELETE', 'INSERT', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE'],
  'authenticated privileges on backup_metadata');

-- The same, spelled with has_table_privilege for the privileges that matter
-- most: both roles can reach the rows, so RLS must hold.
select ok(has_table_privilege('anon', 'public.profiles', 'select'), 'anon can select profiles (RLS filters)');
select ok(has_table_privilege('authenticated', 'public.backup_metadata', 'insert'), 'authenticated can insert backup_metadata (RLS checks)');

-- handle_new_user is a trigger function, so it cannot be called directly
-- even with execute.
select function_privs_are('public', 'handle_new_user', array[]::text[], 'anon', array['EXECUTE'],
  'anon execute on handle_new_user');
select function_privs_are('public', 'handle_new_user', array[]::text[], 'authenticated', array['EXECUTE'],
  'authenticated execute on handle_new_user');
select is(
  (select prosecdef from pg_proc where oid = 'public.handle_new_user()'::regprocedure),
  true,
  'handle_new_user is security definer'
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

select * from finish();
rollback;
