-- coder, reached the three ways it is reached: the web as a signed-in
-- person (tables under RLS, and two functions), and an Edge Function as
-- service_role on a machine's behalf.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(41);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

-- Results carried across a change of role.
create temporary table carried (name text primary key, value jsonb);
grant select, insert, delete on carried to authenticated, service_role;

create function pg_temp.as_person(id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_edge_function() returns void language sql as $$
  select set_config('role', 'service_role', true),
         set_config('request.jwt.claims', '{"role": "service_role"}', true);
$$;

-- What the Edge Function hashes: a key as it is, a code as normalised.
create function pg_temp.h(value text) returns bytea language sql as $$
  select sha256(convert_to(value, 'UTF8'));
$$;

create function pg_temp.code_hash(key text) returns bytea language sql as $$
  select pg_temp.h(replace(value ->> 'code', '-', '')) from carried where name = key;
$$;


-- ------------------------------------------------------------
-- Who may call what. These go over every function in public, so one added
-- later without its revoke fails here. Trigger functions are left out: they
-- cannot be called except as a trigger.
-- ------------------------------------------------------------
create view pg_temp.callable as
  select p.proname::text as name,
         has_function_privilege('anon', p.oid, 'execute') as anon,
         has_function_privilege('authenticated', p.oid, 'execute') as authenticated,
         has_function_privilege('service_role', p.oid, 'execute') as service_role
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and p.prorettype <> 'trigger'::regtype;

select is_empty($$ select name from pg_temp.callable where anon $$,
  'anon can call no function in public');

select set_eq($$ select name from pg_temp.callable where authenticated $$,
  array['create_enrollment_code', 'usage'],
  'a signed-in person can call only create_enrollment_code and usage');

select set_eq($$ select name from pg_temp.callable where service_role and not authenticated $$,
  array['redeem_enrollment_code', 'ingest'],
  'redeem_enrollment_code and ingest are for the Edge Functions alone');

select is_empty(
  $$ select grantee || ' ' || privilege_type || ' on ' || table_name
       from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name in ('providers', 'devices', 'enrollment_codes', 'usage_rollups')
        and grantee = 'anon' $$,
  'anon holds no privilege on the coder tables');

select is_empty(
  $$ select privilege_type || ' on ' || table_name
       from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name in ('providers', 'devices', 'enrollment_codes', 'usage_rollups')
        and grantee = 'authenticated'
        and privilege_type not in ('SELECT', 'UPDATE') $$,
  'a signed-in person can only read and update, never insert, delete or truncate');

select ok(not has_table_privilege('authenticated', 'public.enrollment_codes', 'select'),
  'nobody reads enrollment codes directly');
select ok(not has_column_privilege('authenticated', 'public.devices', 'api_key_hash', 'select'),
  'a browser cannot read key digests');
select ok(not has_column_privilege('authenticated', 'public.devices', 'user_id', 'update'),
  'a machine cannot be handed to another account');


-- ------------------------------------------------------------
-- Enrollment codes, from the web
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
insert into carried select 'code_a', public.create_enrollment_code();

select matches((select value ->> 'code' from carried where name = 'code_a'),
  '^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$',
  'a code is eight characters from the unambiguous alphabet, split in half');

delete from carried where name = 'code_a';
insert into carried select 'code_a', public.create_enrollment_code();
reset role;
select results_eq(
  $$ select count(*)::integer from public.enrollment_codes where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  $$ values (1) $$,
  'asking again replaces the account''s code rather than adding one');

select results_eq(
  $$ select code_hash from public.enrollment_codes where user_id = '00000000-0000-0000-0000-00000000000a' $$,
  $$ select pg_temp.code_hash('code_a') $$,
  'what is stored is the sha256 of the code without its dash');


-- ------------------------------------------------------------
-- Redemption, from the Edge Function
-- ------------------------------------------------------------
select pg_temp.as_edge_function();

select is(
  public.redeem_enrollment_code(pg_temp.h('nobody'), '11111111-1111-1111-1111-111111111111', 'laptop', pg_temp.h('key-a')),
  '{"outcome": "code_invalid"}'::jsonb, 'a code nobody was given is refused');

select is(
  public.redeem_enrollment_code(pg_temp.code_hash('code_a'), '11111111-1111-1111-1111-111111111111', 'laptop', pg_temp.h('key-a')),
  '{"outcome": "redeemed", "user_id": "00000000-0000-0000-0000-00000000000a"}'::jsonb,
  'a code registers the machine to the account that asked for it');

select is(
  public.redeem_enrollment_code(pg_temp.code_hash('code_a'), '22222222-2222-2222-2222-222222222222', 'other', pg_temp.h('key-x')),
  '{"outcome": "code_invalid"}'::jsonb, 'a code works once');

reset role;
select results_eq(
  $$ select user_id, name, api_key_hash from public.devices where id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values ('00000000-0000-0000-0000-00000000000a'::uuid, 'laptop', pg_temp.h('key-a')) $$,
  'the machine is stored with its name and the hash of its key');

select pg_temp.as_person('00000000-0000-0000-0000-00000000000b');
insert into carried select 'code_b', public.create_enrollment_code();
select pg_temp.as_edge_function();
select is(
  public.redeem_enrollment_code(pg_temp.code_hash('code_b'), '11111111-1111-1111-1111-111111111111', 'mine now', pg_temp.h('key-b')),
  '{"outcome": "device_taken"}'::jsonb, 'a machine of another account cannot be taken');

reset role;
select results_eq(
  $$ select count(*)::integer from public.enrollment_codes where code_hash = pg_temp.code_hash('code_b') $$,
  $$ values (1) $$,
  'a redemption that fails does not spend the code');

-- B gets a machine of their own for the checks further down.
select pg_temp.as_edge_function();
select is(
  public.redeem_enrollment_code(pg_temp.code_hash('code_b'), '33333333-3333-3333-3333-333333333333', 'desktop', pg_temp.h('key-b')),
  '{"outcome": "redeemed", "user_id": "00000000-0000-0000-0000-00000000000b"}'::jsonb,
  'the same code still works for a machine that is free');

reset role;
select pg_temp.as_person('00000000-0000-0000-0000-00000000000b');
insert into carried select 'code_b2', public.create_enrollment_code();
reset role;
update public.enrollment_codes
   set created_at = now() - interval '1 hour', expires_at = now() - interval '1 minute'
 where code_hash = pg_temp.code_hash('code_b2');
select pg_temp.as_edge_function();
select is(
  public.redeem_enrollment_code(pg_temp.code_hash('code_b2'), '44444444-4444-4444-4444-444444444444', 'late', pg_temp.h('key-late')),
  '{"outcome": "code_invalid"}'::jsonb, 'an expired code is refused like any other');


-- ------------------------------------------------------------
-- Ingest, from the Edge Function
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


-- ------------------------------------------------------------
-- The web's own reads and changes
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select results_eq(
  $$ select id, name from public.devices $$,
  $$ values ('11111111-1111-1111-1111-111111111111'::uuid, 'laptop') $$,
  'a person sees their own machines and nobody else''s');

select results_eq(
  $$ update public.devices set name = 'work laptop' where id = '11111111-1111-1111-1111-111111111111' returning name $$,
  $$ values ('work laptop') $$,
  'a person can rename their machine');

select is_empty(
  $$ update public.devices set name = 'mine' where id = '33333333-3333-3333-3333-333333333333' returning id $$,
  'a person cannot rename someone else''s machine');

select throws_ok(
  $$ update public.devices set api_key_hash = '\x00' where id = '11111111-1111-1111-1111-111111111111' $$,
  '42501', null, 'a person cannot touch a machine''s key');

select results_eq(
  $$ update public.devices set revoked_at = '2099-01-01' where id = '11111111-1111-1111-1111-111111111111'
     returning revoked_at <= now() $$,
  $$ values (true) $$,
  'retiring a machine stamps it now, whatever time was sent');

select throws_like(
  $$ update public.devices set revoked_at = null where id = '11111111-1111-1111-1111-111111111111' $$,
  '%enrolling it again%', 'a retired machine cannot be brought back by clearing the column');

select pg_temp.as_edge_function();
select is(
  public.ingest(pg_temp.h('key-a'), '[{"provider": "claude_code", "hour_bucket": "2026-09-12T16:00:00Z", "tokens": 1}]'),
  '{"outcome": "unauthorized"}'::jsonb, 'a retired machine''s key is refused');


-- ------------------------------------------------------------
-- Enrolling the same machine again
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
delete from carried where name = 'code_a';
insert into carried select 'code_a', public.create_enrollment_code();
select pg_temp.as_edge_function();
select is(
  public.redeem_enrollment_code(pg_temp.code_hash('code_a'), '11111111-1111-1111-1111-111111111111', 'laptop 2', pg_temp.h('key-a2')),
  '{"outcome": "redeemed", "user_id": "00000000-0000-0000-0000-00000000000a"}'::jsonb,
  'the account that owns a machine can enrol it again');

reset role;
select results_eq(
  $$ select name, api_key_hash, revoked_at from public.devices where id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values ('laptop 2', pg_temp.h('key-a2'), null::timestamptz) $$,
  'enrolling again takes the new name and key, and brings the machine back');

select pg_temp.as_edge_function();
select is(
  public.ingest(pg_temp.h('key-a'), '[{"provider": "claude_code", "hour_bucket": "2026-09-20T00:00:00Z", "tokens": 1}]'),
  '{"outcome": "unauthorized"}'::jsonb, 'the old key stays dead');

select is(
  public.ingest(pg_temp.h('key-a2'), '[{"provider": "claude_code", "hour_bucket": "2026-09-20T00:00:00Z", "tokens": 1}]'),
  '{"outcome": "accepted", "accepted": 1}'::jsonb, 'the new key works');


-- ------------------------------------------------------------
-- Usage, from the web
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
select is(
  public.usage('2026-09-12T00:00:00Z', '2026-09-13T00:00:00Z'),
  '{"from": "2026-09-12T00:00:00Z", "to": "2026-09-13T00:00:00Z", "total": "3200007",
    "devices": [{"device_id": "11111111-1111-1111-1111-111111111111", "device_name": "laptop 2", "tokens": 3200007}],
    "hours": [{"hour_bucket": "2026-09-12T14:00:00Z", "tokens": 3200000},
              {"hour_bucket": "2026-09-12T15:00:00Z", "tokens": 7}]}'::jsonb,
  'usage sums the range per machine and per hour, over the caller''s rows only');

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
