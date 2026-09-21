-- pokecoder's API, called the way PostgREST calls it: as anon or
-- authenticated, with the claims and headers PostgREST would set. What this
-- cannot see is the HTTP status each error becomes; that is PostgREST's
-- translation of the PGRST error, and the code inside it is checked here.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(28);

-- Two accounts, so that one can try to reach the other's rows.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

-- Results carried from one role's call to the next.
create temporary table carried (name text primary key, value jsonb);
grant select, insert, delete on carried to anon, authenticated;

create function pg_temp.as_user(id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true),
         set_config('request.headers', '{}', true);
$$;

create function pg_temp.as_machine(api_key text) returns void language sql as $$
  select set_config('role', 'anon', true),
         set_config('request.jwt.claims', '{"role": "anon"}', true),
         set_config('request.headers', coalesce(json_build_object('x-api-key', api_key)::text, '{}'), true);
$$;

create function pg_temp.carried(key text) returns jsonb language sql as $$
  select value from carried where name = key;
$$;


-- ------------------------------------------------------------
-- Who may call what
-- ------------------------------------------------------------
select ok(not has_function_privilege('anon', 'api.create_enrollment_code()', 'execute'),
  'anon cannot mint an enrollment code');
select ok(not has_function_privilege('anon', 'api.usage(jsonb, jsonb)', 'execute'),
  'anon cannot read usage');
select ok(not has_function_privilege('authenticated', 'api.ingest(jsonb)', 'execute'),
  'a session cannot ingest; only a machine key can');
select ok(not has_function_privilege('anon', 'private.digest(text)', 'execute'),
  'private helpers are not executable by PUBLIC');
select ok(not has_column_privilege('authenticated', 'public.devices', 'api_key_hash', 'select'),
  'a browser cannot read key digests');
select ok(not has_table_privilege('authenticated', 'public.enrollment_codes', 'select'),
  'nobody reads enrollment codes directly');


-- ------------------------------------------------------------
-- Enrollment
-- ------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
insert into carried select 'code', api.create_enrollment_code();

select matches(pg_temp.carried('code') ->> 'code', '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$',
  'a code is eight characters from the unambiguous alphabet, split in half');

select lives_ok($$ select api.create_enrollment_code() $$,
  'asking again reuses the account''s slot instead of failing on it');
reset role;
select is((select count(*)::integer from public.enrollment_codes
            where user_id = '00000000-0000-0000-0000-00000000000a'), 1,
  'an account holds one code at a time');

-- The second request replaced the first code.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
delete from carried where name = 'code';
insert into carried select 'code', api.create_enrollment_code();

select pg_temp.as_machine(null);
select throws_like(
  $$ select api.redeem_enrollment_code('ZZZZ-ZZZZ', '11111111-1111-1111-1111-111111111111', 'laptop') $$,
  '%enrollment_code_invalid%', 'a code nobody was given is refused');

select throws_like(
  $$ select api.redeem_enrollment_code('ABCD-EFGH', 'not-a-uuid', 'laptop') $$,
  '%device_id must be a UUID%', 'a machine id that is not a UUID is refused by name');

-- Typed the way a person might: lower case, no dash, 0 read as O, padded.
insert into carried
select 'machine', api.redeem_enrollment_code(
  '  ' || replace(lower(replace(pg_temp.carried('code') ->> 'code', '-', '')), '0', 'o') || ' ',
  '11111111-1111-1111-1111-111111111111',
  '  laptop  ');

select matches(pg_temp.carried('machine') ->> 'api_key', '^pkt_[0-9a-f]{64}$',
  'redeeming a code hands back a pkt_ key');
select is(pg_temp.carried('machine') ->> 'device_name', 'laptop',
  'the machine''s name is trimmed');

select throws_like(
  format($$ select api.redeem_enrollment_code(%L, '22222222-2222-2222-2222-222222222222', 'other') $$,
         pg_temp.carried('code') ->> 'code'),
  '%enrollment_code_invalid%', 'a code works once');

-- Account B tries to claim A's machine id.
select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
insert into carried select 'code_b', api.create_enrollment_code();
select pg_temp.as_machine(null);
select throws_like(
  format($$ select api.redeem_enrollment_code(%L, '11111111-1111-1111-1111-111111111111', 'mine now') $$,
         pg_temp.carried('code_b') ->> 'code'),
  '%device_owned_by_another_account%', 'a machine id already registered cannot be taken');

reset role;
select is((select count(*)::integer from public.enrollment_codes
            where user_id = '00000000-0000-0000-0000-00000000000b'), 1,
  'a redemption that fails does not spend the code');

reset role;
update public.enrollment_codes set created_at = now() - interval '1 hour', expires_at = now() - interval '1 minute'
 where user_id = '00000000-0000-0000-0000-00000000000b';
select pg_temp.as_machine(null);
select throws_like(
  format($$ select api.redeem_enrollment_code(%L, '33333333-3333-3333-3333-333333333333', 'late') $$,
         pg_temp.carried('code_b') ->> 'code'),
  '%enrollment_code_invalid%', 'an expired code is refused like any other');


-- ------------------------------------------------------------
-- Ingest
-- ------------------------------------------------------------
select pg_temp.as_machine(null);
select throws_like($$ select api.ingest('[]') $$, '%x-api-key header is required%',
  'ingest without a key is refused');

select pg_temp.as_machine('pkt_nope');
select throws_like($$ select api.ingest('[]') $$, '%unknown or revoked API key%',
  'ingest with an unknown key is refused');

select pg_temp.as_machine(pg_temp.carried('machine') ->> 'api_key');
select is(
  api.ingest('[{"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 3200000},
               {"provider": "claude_code", "hour_bucket": "2026-09-12T15:00:00+00:00", "tokens": 5}]'),
  '{"accepted": 2}'::jsonb, 'ingest accepts hourly totals');

select is(
  api.ingest('[{"provider": "claude_code", "hour_bucket": "2026-09-12T15:00:00Z", "tokens": 7}]'),
  '{"accepted": 1}'::jsonb, 'sending a bucket again replaces its total');

select throws_like(
  $$ select api.ingest('[{"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 1},
                         {"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00+00:00", "tokens": 2}]') $$,
  '%rollups[1] repeats claude_code at 2026-09-12T14:00:00Z%', 'one request cannot carry a bucket twice');

select throws_like(
  $$ select api.ingest('[{"provider": "claude_code", "hour_bucket": "infinity", "tokens": 1}]') $$,
  '%rollups[0].hour_bucket is not a valid timestamp%', 'infinity is not an hour');

select throws_like(
  $$ select api.ingest('[{"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00+05:30", "tokens": 1}]') $$,
  '%must be on the hour in UTC%', 'an hour in a half-hour zone is not an hour in UTC');

select throws_like(
  $$ select api.ingest('[{"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 9007199254740992}]') $$,
  '%rollups[0].tokens must be a whole number%', 'a count past 2^53 has already lost precision');

select throws_like(
  $$ select api.ingest('[{"provider": "nope", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 1}]') $$,
  '%unknown provider %nope%; known providers are claude_code%', 'an unknown provider is named');


-- ------------------------------------------------------------
-- Usage
-- ------------------------------------------------------------
select pg_temp.as_user('00000000-0000-0000-0000-00000000000a');
select is(
  api.usage('"2026-09-12T00:00:00Z"', '"2026-09-13T00:00:00Z"') - 'devices',
  '{"from": "2026-09-12T00:00:00Z", "to": "2026-09-13T00:00:00Z", "total": "3200007",
    "hours": [{"hour_bucket": "2026-09-12T14:00:00Z", "tokens": 3200000},
              {"hour_bucket": "2026-09-12T15:00:00Z", "tokens": 7}]}'::jsonb,
  'usage sums the range by hour, with the total as a string');

select pg_temp.as_user('00000000-0000-0000-0000-00000000000b');
select is(
  api.usage('"2026-09-12T00:00:00Z"', '"2026-09-13T00:00:00Z"') ->> 'total', '0',
  'another account sees none of it');

select * from finish();
rollback;
