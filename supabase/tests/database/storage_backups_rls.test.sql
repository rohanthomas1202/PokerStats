-- storage.objects in the backups bucket: the four backups_*_own policies
-- (20260420000000_init_schema.sql). Files live under <user_id>/.
begin;
select plan(9);

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a@example.invalid'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b@example.invalid');
insert into storage.objects (bucket_id, name) values
  ('backups', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a.json'),
  ('backups', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/b.json');

-- The Storage API sets this before a delete; without it the
-- protect_objects_delete trigger refuses every direct delete, and the delete
-- policy would never be reached.
set local storage.allow_delete_query = 'true';

select results_eq(
  $$select public from storage.buckets where id = 'backups'$$,
  array[false],
  'the backups bucket is private'
);

-- As B.
set local role authenticated;
set local request.jwt.claims = '{"sub": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "role": "authenticated"}';

select results_eq(
  $$select name from storage.objects where bucket_id = 'backups'$$,
  $$values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/b.json'::text)$$,
  'B sees its own file and no other'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('backups', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/x.json')$$,
  '42501', null,
  'B cannot upload into A''s folder'
);
select throws_ok(
  $$update storage.objects set name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/moved.json'
    where name = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb/b.json'$$,
  '42501', null,
  'B cannot move its own file into A''s folder'
);
update storage.objects set metadata = '{"x": 1}' where name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a.json';
delete from storage.objects where name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a.json';

-- As anon.
set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is_empty($$select 1 from storage.objects where bucket_id = 'backups'$$, 'anon sees no backup files');
select throws_ok(
  $$insert into storage.objects (bucket_id, name) values ('backups', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/y.json')$$,
  '42501', null,
  'anon cannot upload a backup file'
);
delete from storage.objects where bucket_id = 'backups';

reset role;

select results_eq(
  $$select metadata from storage.objects where name = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/a.json'$$,
  array[null::jsonb],
  'B''s update and B''s and anon''s deletes left A''s file unchanged'
);
select results_eq(
  $$select count(*)::int from storage.objects where bucket_id = 'backups'$$,
  array[2],
  'no file was added or removed'
);
select ok(
  (select array_agg(policyname::text order by policyname) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'backups\_%')
    = array['backups_delete_own', 'backups_insert_own', 'backups_select_own', 'backups_update_own'],
  'storage.objects has the four backups own-folder policies'
);

select * from finish();
rollback;
