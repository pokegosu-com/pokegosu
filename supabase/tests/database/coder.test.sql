-- coder's ledger: what a machine uploads through the ingest Edge Function,
-- and what the web reads back.
--
-- Machines and their keys belong to the account, not to coder, so the setup
-- here enrols one the way the account's Edge Function would and then speaks
-- only as coder does: with a key hash on the way in, and a session on the
-- way out.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(13);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

create function pg_temp.h(value text) returns bytea language sql as $$
  select sha256(convert_to(value, 'UTF8'));
$$;

create function pg_temp.as_person(id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_edge_function() returns void language sql as $$
  select set_config('role', 'service_role', true),
         set_config('request.jwt.claims', '{"role": "service_role"}', true);
$$;

-- One machine each, enrolled as the account's Edge Function would.
insert into public.devices (id, user_id, name, api_key_hash) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a', 'laptop', pg_temp.h('key-a')),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-00000000000b', 'desktop', pg_temp.h('key-b'));

select pg_temp.as_edge_function();


-- ------------------------------------------------------------
-- Ingest
-- ------------------------------------------------------------
select is(
  public.ingest(pg_temp.h('key-nope'), '[{"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 1}]'),
  '{"outcome": "unauthorized"}'::jsonb, 'an unknown key is refused');

select is(
  public.ingest(pg_temp.h('key-a'),
    '[{"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 3200000},
      {"provider": "claude_code", "hour_bucket": "2026-09-12T15:00:00Z", "tokens": 5}]'),
  '{"outcome": "accepted", "accepted": 2}'::jsonb, 'hourly totals are accepted');

select is(
  public.ingest(pg_temp.h('key-a'), '[{"provider": "claude_code", "hour_bucket": "2026-09-12T15:00:00Z", "tokens": 7}]'),
  '{"outcome": "accepted", "accepted": 1}'::jsonb, 'a bucket can be sent again');

select is(
  public.ingest(pg_temp.h('key-b'), '[{"provider": "claude_code", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 9}]'),
  '{"outcome": "accepted", "accepted": 1}'::jsonb, 'another account''s machine records its own');

reset role;
select results_eq(
  $$ select hour_bucket, tokens::bigint from public.usage_rollups
      where device_id = '11111111-1111-1111-1111-111111111111' order by hour_bucket $$,
  $$ values ('2026-09-12T14:00:00Z'::timestamptz, 3200000::bigint), ('2026-09-12T15:00:00Z', 7) $$,
  'sending a bucket again replaces its total rather than adding to it');

select isnt(
  (select last_sync_at from public.devices where id = '11111111-1111-1111-1111-111111111111'), null,
  'the machine''s last sync is recorded');

select pg_temp.as_edge_function();
select is(
  public.ingest(pg_temp.h('key-a'), '[{"provider": "nope", "hour_bucket": "2026-09-12T14:00:00Z", "tokens": 1}]'),
  '{"outcome": "unknown_provider", "provider": "nope", "known": ["claude_code"]}'::jsonb,
  'an unknown provider is named, with the ones that exist');

-- Retiring is the account's doing; coder only has to stop taking the key.
reset role;
update public.devices set revoked_at = now() where id = '11111111-1111-1111-1111-111111111111';
select pg_temp.as_edge_function();
select is(
  public.ingest(pg_temp.h('key-a'), '[{"provider": "claude_code", "hour_bucket": "2026-09-12T16:00:00Z", "tokens": 1}]'),
  '{"outcome": "unauthorized"}'::jsonb, 'a retired machine''s key is refused');


-- ------------------------------------------------------------
-- Usage, from the web
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
select is(
  public.usage('2026-09-12T00:00:00Z', '2026-09-13T00:00:00Z'),
  '{"from": "2026-09-12T00:00:00Z", "to": "2026-09-13T00:00:00Z", "total": "3200007",
    "devices": [{"device_id": "11111111-1111-1111-1111-111111111111", "device_name": "laptop", "tokens": 3200007}],
    "hours": [{"hour_bucket": "2026-09-12T14:00:00Z", "tokens": 3200000},
              {"hour_bucket": "2026-09-12T15:00:00Z", "tokens": 7}]}'::jsonb,
  'usage sums the range per machine and per hour, over the caller''s rows only');

select is(
  public.usage('2026-09-12T00:00:00Z', '2026-09-13T00:00:00Z') ->> 'total', '3200007',
  'a retired machine''s history still counts');

select pg_temp.as_person('00000000-0000-0000-0000-00000000000b');
select is(
  public.usage('2026-09-12T00:00:00Z', '2026-09-13T00:00:00Z') ->> 'total', '9',
  'another account sees only its own');

select throws_ok(
  $$ select public.usage('2026-09-13T00:00:00Z', '2026-09-12T00:00:00Z') $$,
  '22023', 'range_end must be after range_start', 'a backwards range is refused');

select throws_ok(
  $$ select public.usage('2026-09-12T00:30:00Z', '2026-09-13T00:00:00Z') $$,
  '22023', 'range_start and range_end must be on the hour in UTC', 'a range off the hour is refused');

select * from finish();
rollback;
