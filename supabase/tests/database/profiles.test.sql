-- A profile: a handle chosen once, and a display name that is never blank
-- beside it.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(7);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

create function pg_temp.as_person(id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true);
$$;

select results_eq(
  $$ select username, display_name from public.profiles where id = '00000000-0000-0000-0000-00000000000a' $$,
  $$ values (null::text, null::text) $$,
  'a new account has a profile with neither yet');

select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select results_eq(
  $$ update public.profiles set username = 'abc', display_name = null
      where id = '00000000-0000-0000-0000-00000000000a' returning display_name $$,
  $$ values ('@abc') $$,
  'a handle chosen with no name names them after it');

select results_eq(
  $$ update public.profiles set display_name = '앨리스'
      where id = '00000000-0000-0000-0000-00000000000a' returning display_name $$,
  $$ values ('앨리스') $$,
  'the name can be changed');

select results_eq(
  $$ update public.profiles set display_name = '   '
      where id = '00000000-0000-0000-0000-00000000000a' returning display_name $$,
  $$ values ('@abc') $$,
  'cleared, it is the handle again');

select throws_like(
  $$ update public.profiles set username = 'abd' where id = '00000000-0000-0000-0000-00000000000a' $$,
  '%username cannot be changed once set%', 'the handle cannot be changed');

select pg_temp.as_person('00000000-0000-0000-0000-00000000000b');

select results_eq(
  $$ update public.profiles set username = 'bcd', display_name = '  밥  '
      where id = '00000000-0000-0000-0000-00000000000b' returning display_name $$,
  $$ values ('  밥  ') $$,
  'a name given is kept as given');

reset role;
select throws_like(
  $$ alter table public.profiles disable trigger profiles_default_display_name;
     update public.profiles set display_name = '' where id = '00000000-0000-0000-0000-00000000000b' $$,
  '%profiles_display_name_required%', 'past the trigger, the table still refuses a blank name');

select * from finish();
rollback;
