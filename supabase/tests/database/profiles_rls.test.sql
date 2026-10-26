-- public.profiles: row-level security (20260420000000_init_schema.sql).
-- User A owns a row, user B and anon try to read and change it.
begin;
select plan(13);

-- Users A and B. The on_auth_user_created trigger gives each a profile.
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a@example.invalid'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'b@example.invalid');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'RLS is enabled on profiles'
);
select results_eq(
  $$select count(*)::int from public.profiles
    where id in ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$$,
  array[2],
  'handle_new_user creates one profile per new user'
);

-- As B.
set local role authenticated;
set local request.jwt.claims = '{"sub": "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", "role": "authenticated"}';

select results_eq(
  'select id from public.profiles',
  $$values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'::uuid)$$,
  'B sees its own profile and no other'
);
select is_empty(
  $$select 1 from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'B cannot select A''s profile by id'
);

update public.profiles set last_backup_at = '2026-01-01T00:00:00Z' where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
update public.profiles set last_backup_at = '2026-01-02T00:00:00Z' where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
delete from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

select throws_ok(
  $$insert into public.profiles (id) values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc')$$,
  '42501', null,
  'B cannot insert a profile for another id'
);
select throws_ok(
  $$update public.profiles set id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
    where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$$,
  '42501', null,
  'B cannot move its own profile to A''s id'
);

-- As anon: no JWT subject.
set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select is_empty('select 1 from public.profiles', 'anon sees no profiles');
select throws_ok(
  $$insert into public.profiles (id) values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc')$$,
  '42501', null,
  'anon cannot insert a profile'
);
update public.profiles set last_backup_at = '2026-01-03T00:00:00Z';
delete from public.profiles;

-- Back to the table owner to check what B and anon changed.
reset role;

select is(
  (select last_backup_at from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
  null,
  'B''s and anon''s updates left A''s profile unchanged'
);
select is(
  (select last_backup_at from public.profiles where id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  '2026-01-02T00:00:00Z'::timestamptz,
  'B can update its own profile'
);
select isnt_empty(
  $$select 1 from public.profiles where id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$$,
  'B''s and anon''s deletes left A''s profile in place'
);
select results_eq(
  'select count(*)::int from public.profiles where id = ''cccccccc-cccc-4ccc-8ccc-cccccccccccc''',
  array[0],
  'no profile was inserted for the other id'
);
select policies_are(
  'public', 'profiles',
  array['profiles_select_own', 'profiles_insert_own', 'profiles_update_own', 'profiles_delete_own'],
  'profiles has exactly the four own-row policies'
);

select * from finish();
rollback;
