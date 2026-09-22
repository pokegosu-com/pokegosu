-- The pokecoder schema, called the way the API app calls it: as service_role,
-- with arguments the app has already checked, codes and keys already hashed.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(24);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

-- Stand-ins for what the app would hash.
create function pg_temp.h(value text) returns bytea language sql as $$
  select sha256(convert_to(value, 'UTF8'));
$$;


-- ------------------------------------------------------------
-- Who may call what. These go over every function and table, so one added
-- later without its revoke fails here.
-- ------------------------------------------------------------
select is_empty(
  $$ select p.oid::regprocedure from pg_proc p
      where p.pronamespace = 'pokecoder'::regnamespace
        and (has_function_privilege('anon', p.oid, 'execute')
          or has_function_privilege('authenticated', p.oid, 'execute')) $$,
  'no pokecoder function is executable by anon or authenticated');

select is_empty(
  $$ select p.oid::regprocedure from pg_proc p
      where p.pronamespace = 'pokecoder'::regnamespace
        and not has_function_privilege('service_role', p.oid, 'execute') $$,
  'every pokecoder function is executable by service_role');

select is_empty(
  $$ select grantee || ' ' || privilege_type || ' on ' || table_name
       from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name in ('providers', 'devices', 'enrollment_codes', 'usage_rollups')
        and grantee in ('anon', 'authenticated') $$,
  'anon and authenticated hold no privilege on the pokecoder tables');

set local role anon;
select throws_ok(
  $$ select pokecoder.ingest('\x00', '[]') $$, '42501', null,
  'anon is refused at the door');
reset role;

-- The functions are called as service_role, the way the app calls them. It
-- holds no privilege on the tables themselves, so checks that look at a table
-- directly step back out to the owner first.
set local role service_role;


-- ------------------------------------------------------------
-- Enrollment codes
-- ------------------------------------------------------------
select is(
  pokecoder.create_enrollment_code('00000000-0000-0000-0000-00000000000a', pg_temp.h('A1'), now() + interval '10 minutes'),
  '{"outcome": "created"}'::jsonb, 'a code is stored');

select is(
  pokecoder.create_enrollment_code('00000000-0000-0000-0000-00000000000a', pg_temp.h('A2'), now() + interval '10 minutes'),
  '{"outcome": "created"}'::jsonb, 'asking again reuses the account''s slot instead of failing on it');

reset role;
select results_eq(
  $$ select code_hash from public.enrollment_codes where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  $$ values (pg_temp.h('A2')) $$,
  'an account holds one code at a time, the latest');
set local role service_role;

select is(
  pokecoder.create_enrollment_code('00000000-0000-0000-0000-00000000000b', pg_temp.h('A2'), now() + interval '10 minutes'),
  '{"outcome": "collision"}'::jsonb, 'a code another account holds is reported, so the app can draw again');


-- ------------------------------------------------------------
-- Redemption
-- ------------------------------------------------------------
select is(
  pokecoder.redeem_enrollment_code(pg_temp.h('nobody'), '11111111-1111-1111-1111-111111111111', 'laptop', pg_temp.h('key-a')),
  '{"outcome": "code_invalid"}'::jsonb, 'a code nobody was given is refused');

select is(
  pokecoder.redeem_enrollment_code(pg_temp.h('A2'), '11111111-1111-1111-1111-111111111111', 'laptop', pg_temp.h('key-a')),
  '{"outcome": "redeemed", "user_id": "00000000-0000-0000-0000-00000000000a"}'::jsonb,
  'a code registers the machine to the account that asked for it');

reset role;
select results_eq(
  $$ select user_id, name, api_key_hash from public.devices where id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values ('00000000-0000-0000-0000-00000000000a'::uuid, 'laptop', pg_temp.h('key-a')) $$,
  'the machine is stored with its name and the hash of its key');
set local role service_role;

select is(
  pokecoder.redeem_enrollment_code(pg_temp.h('A2'), '22222222-2222-2222-2222-222222222222', 'other', pg_temp.h('key-x')),
  '{"outcome": "code_invalid"}'::jsonb, 'a code works once');

do $$ begin
  perform pokecoder.create_enrollment_code('00000000-0000-0000-0000-00000000000b', pg_temp.h('B1'), now() + interval '10 minutes');
end $$;
select is(
  pokecoder.redeem_enrollment_code(pg_temp.h('B1'), '11111111-1111-1111-1111-111111111111', 'mine now', pg_temp.h('key-b')),
  '{"outcome": "device_taken"}'::jsonb, 'a machine id already registered cannot be taken');

reset role;
select results_eq(
  $$ select count(*)::integer from public.enrollment_codes where code_hash = pg_temp.h('B1') $$,
  $$ values (1) $$,
  'a redemption that fails does not spend the code');

update public.enrollment_codes
   set created_at = now() - interval '1 hour', expires_at = now() - interval '1 minute'
 where code_hash = pg_temp.h('B1');
set local role service_role;

select is(
  pokecoder.redeem_enrollment_code(pg_temp.h('B1'), '33333333-3333-3333-3333-333333333333', 'late', pg_temp.h('key-b')),
  '{"outcome": "code_invalid"}'::jsonb, 'an expired code is refused like any other');


-- ------------------------------------------------------------
-- Ingest
-- ------------------------------------------------------------
select is(
  pokecoder.ingest(pg_temp.h('key-nope'), '[{"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 1}]'),
  '{"outcome": "unauthorized"}'::jsonb, 'an unknown key is refused');

select is(
  pokecoder.ingest(pg_temp.h('key-a'),
    '[{"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 3200000},
      {"provider": "claude_code", "hour_bucket": "2026-09-12T15:00:00Z", "tokens": 5}]'),
  '{"outcome": "accepted", "accepted": 2}'::jsonb, 'hourly totals are accepted');

select is(
  pokecoder.ingest(pg_temp.h('key-a'), '[{"provider": "claude_code", "hour_bucket": "2026-09-12T15:00:00Z", "tokens": 7}]'),
  '{"outcome": "accepted", "accepted": 1}'::jsonb, 'a bucket can be sent again');

reset role;
select results_eq(
  $$ select hour_bucket, tokens::bigint from public.usage_rollups
      where device_id = '11111111-1111-1111-1111-111111111111' order by hour_bucket $$,
  $$ values ('2026-09-12T14:00:00Z'::timestamptz, 3200000::bigint), ('2026-09-12T15:00:00Z', 7) $$,
  'sending a bucket again replaces its total rather than adding to it');
set local role service_role;

reset role;
select isnt(
  (select last_sync_at from public.devices where id = '11111111-1111-1111-1111-111111111111'), null,
  'the machine''s last sync is recorded');
set local role service_role;

select is(
  pokecoder.ingest(pg_temp.h('key-a'), '[{"provider": "nope", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 1}]'),
  '{"outcome": "unknown_provider", "provider": "nope", "known": ["claude_code"]}'::jsonb,
  'an unknown provider is named, with the ones that exist');

reset role;
update public.devices set revoked_at = now() where id = '11111111-1111-1111-1111-111111111111';
set local role service_role;

select is(
  pokecoder.ingest(pg_temp.h('key-a'), '[{"provider": "claude_code", "hour_bucket": "2026-09-12T16:00:00Z", "tokens": 1}]'),
  '{"outcome": "unauthorized"}'::jsonb, 'a revoked key is refused like an unknown one');


-- ------------------------------------------------------------
-- Usage
-- ------------------------------------------------------------
select is(
  pokecoder.usage('00000000-0000-0000-0000-00000000000a', '2026-09-12T00:00:00Z', '2026-09-13T00:00:00Z'),
  '{"from": "2026-09-12T00:00:00Z", "to": "2026-09-13T00:00:00Z", "total": "3200007",
    "devices": [{"device_id": "11111111-1111-1111-1111-111111111111", "device_name": "laptop", "tokens": 3200007}],
    "hours": [{"hour_bucket": "2026-09-12T14:00:00Z", "tokens": 3200000},
              {"hour_bucket": "2026-09-12T15:00:00Z", "tokens": 7}]}'::jsonb,
  'usage sums the range per machine and per hour, with the total as a string');

select is(
  pokecoder.usage('00000000-0000-0000-0000-00000000000b', '2026-09-12T00:00:00Z', '2026-09-13T00:00:00Z') ->> 'total', '0',
  'another account sees none of it');

select * from finish();
rollback;
