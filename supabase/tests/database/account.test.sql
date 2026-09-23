-- Enrolling a machine, reached the two ways it is reached: an Edge Function
-- as service_role for a machine that has nothing to authenticate with yet,
-- and the web as the signed-in person who approves it.
--
-- The first three checks are repository-wide rather than about this migration
-- alone: they go over every function in public, so one added anywhere without
-- its revoke fails here.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(39);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

create function pg_temp.as_person(id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.as_edge_function() returns void language sql as $$
  select set_config('role', 'service_role', true),
         set_config('request.jwt.claims', '{"role": "service_role"}', true);
$$;

-- What the Edge Functions hash before anything reaches the database.
create function pg_temp.h(value text) returns bytea language sql as $$
  select sha256(convert_to(value, 'UTF8'));
$$;

-- start <code> <claim> <device id> <name> — a machine asking to be let in.
create function pg_temp.start(code text, claim text, device uuid, name text)
returns jsonb language sql as $$
  select public.start_enrollment(pg_temp.h(code), pg_temp.h(claim), device, name, interval '10 minutes');
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
  array['pending_enrollment', 'approve_enrollment', 'usage'],
  'a signed-in person can only look at a request, approve it, and read usage');

select set_eq($$ select name from pg_temp.callable where service_role and not authenticated $$,
  array['start_enrollment', 'claim_enrollment', 'ingest'],
  'the rest are for the Edge Functions alone');

select is_empty(
  $$ select grantee || ' ' || privilege_type || ' on ' || table_name
       from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name in ('devices', 'enrollments')
        and grantee = 'anon' $$,
  'anon holds no privilege on the machines or the requests');

select is_empty(
  $$ select privilege_type || ' on ' || table_name
       from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name in ('devices', 'enrollments')
        and grantee = 'authenticated'
        and privilege_type not in ('SELECT', 'UPDATE') $$,
  'a signed-in person can only read and update, never insert, delete or truncate');

select ok(not has_table_privilege('authenticated', 'public.enrollments', 'select'),
  'nobody reads the pending requests directly');
select ok(not has_column_privilege('authenticated', 'public.devices', 'api_key_hash', 'select'),
  'a browser cannot read key digests');
select ok(not has_column_privilege('authenticated', 'public.devices', 'user_id', 'update'),
  'a machine cannot be handed to another account');


-- ------------------------------------------------------------
-- A machine asks
-- ------------------------------------------------------------
select pg_temp.as_edge_function();

select is(pg_temp.start('ABCD1234', 'claim-a', '11111111-1111-1111-1111-111111111111', 'laptop') - 'expires_at',
  '{"outcome": "started"}'::jsonb, 'a machine can ask to be let in');

select is(pg_temp.start('ABCD1234', 'claim-other', '22222222-2222-2222-2222-222222222222', 'other'),
  '{"outcome": "code_taken"}'::jsonb, 'two machines cannot wait on one code');

select is(
  public.claim_enrollment(pg_temp.h('claim-a'), pg_temp.h('key-a')),
  '{"outcome": "waiting"}'::jsonb, 'nothing is handed out before a person approves');

select is(
  public.claim_enrollment(pg_temp.h('claim-nobody'), pg_temp.h('key-x')),
  '{"outcome": "not_found"}'::jsonb, 'a claim token nobody was given gets nothing');


-- ------------------------------------------------------------
-- A person approves
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select is(
  public.pending_enrollment('abcd-1234') - 'requested_at',
  '{"outcome": "pending", "device_name": "laptop"}'::jsonb,
  'the screen says which machine is asking, however the code was typed');

select is(
  public.pending_enrollment('ZZZZ-ZZZZ'),
  '{"outcome": "not_found"}'::jsonb, 'a code nobody is waiting on says so');

select is(
  public.approve_enrollment('abcd-1234'),
  '{"outcome": "approved", "device_name": "laptop"}'::jsonb, 'a person lets the machine in');

select is(
  public.approve_enrollment('ABCD-1234'),
  '{"outcome": "not_found"}'::jsonb, 'approving twice does nothing');

select is(
  public.pending_enrollment('ABCD-1234'),
  '{"outcome": "not_found"}'::jsonb, 'an approved request is no longer waiting for anyone');

reset role;
set local role anon;
select throws_ok($$ select public.approve_enrollment('ABCD-1234') $$, '42501', null,
  'approving takes a session');
reset role;


-- ------------------------------------------------------------
-- The machine collects
-- ------------------------------------------------------------
select pg_temp.as_edge_function();

select is(
  public.claim_enrollment(pg_temp.h('claim-a'), pg_temp.h('key-a')) - 'user_id' - 'enrolled_at',
  '{"outcome": "registered", "device_name": "laptop"}'::jsonb,
  'the machine collects its key once it has been let in');

select is(
  public.claim_enrollment(pg_temp.h('claim-a'), pg_temp.h('key-again')),
  '{"outcome": "not_found"}'::jsonb, 'a claim token works once');

reset role;
select results_eq(
  $$ select user_id, name, api_key_hash from public.devices where id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values ('00000000-0000-0000-0000-00000000000a'::uuid, 'laptop', pg_temp.h('key-a')) $$,
  'the machine is stored with its name and the hash of the key it collected');

select is_empty(
  $$ select code_hash from public.enrollments where code_hash = pg_temp.h('ABCD1234') $$,
  'a collected request does not linger');


-- ------------------------------------------------------------
-- A machine another account owns
-- ------------------------------------------------------------
select pg_temp.as_edge_function();
select is(pg_temp.start('BCDE2345', 'claim-b', '11111111-1111-1111-1111-111111111111', 'mine now') - 'expires_at',
  '{"outcome": "started"}'::jsonb, 'anyone may ask about any machine id');

select pg_temp.as_person('00000000-0000-0000-0000-00000000000b');
select is(
  public.approve_enrollment('BCDE-2345'),
  '{"outcome": "approved", "device_name": "mine now"}'::jsonb, 'and anyone may approve their own request');

select pg_temp.as_edge_function();
select is(
  public.claim_enrollment(pg_temp.h('claim-b'), pg_temp.h('key-b')),
  '{"outcome": "device_taken"}'::jsonb, 'but the machine itself stays with the account that has it');

reset role;
select results_eq(
  $$ select user_id, api_key_hash from public.devices where id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values ('00000000-0000-0000-0000-00000000000a'::uuid, pg_temp.h('key-a')) $$,
  'the machine keeps its owner and its key');


-- ------------------------------------------------------------
-- Requests that have run out
-- ------------------------------------------------------------
select pg_temp.as_edge_function();
select is(pg_temp.start('CDEF3456', 'claim-late', '33333333-3333-3333-3333-333333333333', 'late') - 'expires_at',
  '{"outcome": "started"}'::jsonb, 'a machine asks');

reset role;
update public.enrollments
   set created_at = now() - interval '1 hour', expires_at = now() - interval '1 minute'
 where code_hash = pg_temp.h('CDEF3456');

select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
select is(
  public.pending_enrollment('CDEF-3456'),
  '{"outcome": "not_found"}'::jsonb, 'an expired request cannot be approved');

select pg_temp.as_edge_function();
select is(
  public.claim_enrollment(pg_temp.h('claim-late'), pg_temp.h('key-late')),
  '{"outcome": "not_found"}'::jsonb, 'nor collected');

select is(pg_temp.start('DEFG4567', 'claim-sweep', '44444444-4444-4444-4444-444444444444', 'sweeper') - 'expires_at',
  '{"outcome": "started"}'::jsonb, 'a later request comes in');

reset role;
select is_empty($$ select code_hash from public.enrollments where expires_at < now() $$,
  'and the expired ones are swept as it goes');


-- ------------------------------------------------------------
-- What the web may do with a machine it has
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

select throws_ok(
  $$ update public.devices set api_key_hash = '\x00' where id = '11111111-1111-1111-1111-111111111111' $$,
  '42501', null, 'a person cannot touch a machine''s key');

-- ------------------------------------------------------------
-- One id, one enrolment
-- ------------------------------------------------------------
select pg_temp.as_edge_function();
select pg_temp.start('EFGH5678', 'claim-again', '11111111-1111-1111-1111-111111111111', 'laptop 2');

select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
select public.approve_enrollment('EFGH-5678');

select pg_temp.as_edge_function();
select is(
  public.claim_enrollment(pg_temp.h('claim-again'), pg_temp.h('key-a2')),
  '{"outcome": "device_taken"}'::jsonb,
  'a machine id that is registered is not registered again, even by its owner');

reset role;
select results_eq(
  $$ select name, api_key_hash from public.devices where id = '11111111-1111-1111-1111-111111111111' $$,
  $$ values ('work laptop', pg_temp.h('key-a')) $$,
  'the machine keeps the name and key it had');


-- ------------------------------------------------------------
-- Retiring ends it
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select results_eq(
  $$ update public.devices set revoked_at = '2099-01-01' where id = '11111111-1111-1111-1111-111111111111'
     returning revoked_at <= now() $$,
  $$ values (true) $$,
  'retiring a machine stamps it now, whatever time was sent');

select throws_like(
  $$ update public.devices set revoked_at = null where id = '11111111-1111-1111-1111-111111111111' $$,
  '%retiring a machine is final%', 'and it cannot be undone by clearing the column');


-- ------------------------------------------------------------
-- When a machine was let in
-- ------------------------------------------------------------
select pg_temp.as_edge_function();
select pg_temp.start('FGHJ6789', 'claim-first', '55555555-5555-5555-5555-555555555555', 'fresh');

select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
select public.approve_enrollment('FGHJ-6789');

select pg_temp.as_edge_function();
create temporary table collected as
select public.claim_enrollment(pg_temp.h('claim-first'), pg_temp.h('key-first')) as value;

-- A service reads this to know how far back the logs it finds are this
-- machine's to report, so it has to be the moment the account first let it
-- in rather than the moment it last collected a key.
reset role;
select results_eq(
  $$ select value ->> 'enrolled_at' from collected $$,
  $$ select to_char(created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
       from public.devices where id = '55555555-5555-5555-5555-555555555555' $$,
  'collecting says when the machine was first enrolled');

select * from finish();
rollback;
