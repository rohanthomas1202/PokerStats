-- public.backup_metadata: row-level security (20260420000000_init_schema.sql).
-- User A owns a row, user B and anon try to read and change it. There is no
-- update policy, so nobody can update a row through RLS.
begin;
select plan(11);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a@example.invalid'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b@example.invalid');
insert into public.backup_metadata (id, user_id, storage_path, file_size_bytes, schema_version, session_count, hand_count) values
  ('a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a.json', 100, 1, 1, 10),
  ('b1b1b1b1-b1b1-4b1b-8b1b-b1b1b1b1b1b1', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/b.json', 200, 1, 2, 20),
  ('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/c.json', 300, 1, 3, 30);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.backup_metadata'::regclass),
  'RLS is enabled on backup_metadata'
);

-- As B.
set local role authenticated;
set local request.jwt.claims = '{"sub": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "role": "authenticated"}';

select results_eq(
  'select id from public.backup_metadata order by id',
  $$values ('b1b1b1b1-b1b1-4b1b-8b1b-b1b1b1b1b1b1'::uuid), ('b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2'::uuid)$$,
  'B sees its own rows and no others'
);
select is_empty(
  $$select 1 from public.backup_metadata where id = 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1'$$,
  'B cannot select A''s row by id'
);
select throws_ok(
  $$insert into public.backup_metadata (user_id, storage_path, file_size_bytes, schema_version, session_count, hand_count)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/x.json', 1, 1, 0, 0)$$,
  '42501', null,
  'B cannot insert a row for A'
);
select lives_ok(
  $$insert into public.backup_metadata (user_id, storage_path, file_size_bytes, schema_version, session_count, hand_count)
    values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/d.json', 1, 1, 0, 0)$$,
  'B can insert its own row'
);
update public.backup_metadata set hand_count = 999;
delete from public.backup_metadata where id = 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1';
delete from public.backup_metadata where id = 'b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2';

-- As anon.
set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is_empty('select 1 from public.backup_metadata', 'anon sees no rows');
select throws_ok(
  $$insert into public.backup_metadata (user_id, storage_path, file_size_bytes, schema_version, session_count, hand_count)
    values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/y.json', 1, 1, 0, 0)$$,
  '42501', null,
  'anon cannot insert a row'
);
update public.backup_metadata set hand_count = 999;
delete from public.backup_metadata;

reset role;

select results_eq(
  $$select hand_count from public.backup_metadata where id = 'a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1'$$,
  array[10],
  'B''s and anon''s updates and deletes left A''s row unchanged'
);
select results_eq(
  'select count(*)::int from public.backup_metadata where hand_count = 999',
  array[0],
  'no row was updated, B''s own included (no update policy)'
);
select results_eq(
  'select id from public.backup_metadata where user_id = ''bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'' and storage_path <> ''bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/d.json''',
  $$values ('b1b1b1b1-b1b1-4b1b-8b1b-b1b1b1b1b1b1'::uuid)$$,
  'B can delete its own row'
);
select policies_are(
  'public', 'backup_metadata',
  array['backup_metadata_select_own', 'backup_metadata_insert_own', 'backup_metadata_delete_own'],
  'backup_metadata has exactly the select, insert and delete own-row policies'
);

select * from finish();
rollback;
