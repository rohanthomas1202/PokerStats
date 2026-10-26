-- Runs outside the begin/rollback wrapper (see ../README.md), so each
-- statement commits on its own and the connection stays the same.
--
-- Design 3.2 relies on this Postgres behavior: after a transaction-local
-- set_config commits, the setting reads '' (not NULL) for the rest of the
-- connection. The sync trigger must compare to 'on', never check for NULL.
-- Inside one wrapping transaction the 'on' would still be visible, so this
-- can't be a supabase test db file.
select plan(3);

select is(current_setting('pokerstats.test_flag', true), null, 'unset before any set_config');

-- Its own committed transaction (autocommit).
select set_config('pokerstats.test_flag', 'on', true);

select is(current_setting('pokerstats.test_flag', true), '', 'reads empty string after the transaction ends');
select isnt(current_setting('pokerstats.test_flag', true), 'on', 'is no longer on in the next transaction');

select * from finish();
