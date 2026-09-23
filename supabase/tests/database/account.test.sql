-- Machines and their enrolment, reached the two ways they are reached: the
-- web as a signed-in person, and an Edge Function as service_role for a
-- machine that has nothing to authenticate with yet.
--
-- The first three checks are repository-wide rather than about this migration
-- alone: they go over every function in public, so one added anywhere without
-- its revoke fails here.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(27);

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
-- Who may call what. Trigger functions are left out: they cannot be called
-- except as a trigger.
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
        and table_name in ('devices', 'enrollment_codes')
        and grantee = 'anon' $$,
  'anon holds no privilege on the machines or their codes');

select is_empty(
  $$ select privilege_type || ' on ' || table_name
       from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name in ('devices', 'enrollment_codes')
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
-- Asking for a code, from the web
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
-- Spending it, from the Edge Function
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
-- What the web may do with a machine
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


-- ------------------------------------------------------------
-- Enrolling the same machine again
-- ------------------------------------------------------------
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

select * from finish();
rollback;
