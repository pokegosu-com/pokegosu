-- A person's own pokedex: what hatching and evolving write down, and who
-- may read it.
--
-- As in game.test.sql, a companion's species, tokens and level are set
-- directly where a case needs them, rather than rolled or earned.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(11);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

create function pg_temp.as_person(id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.main() returns uuid language sql security definer as $$
  select main_companion_id from public.coder_trainers where user_id = '00000000-0000-0000-0000-00000000000a';
$$;

create function pg_temp.dex() returns text language sql as $$
  select coalesce(string_agg(species_id || case when shiny then '✨' else '' end, ' ' order by species_id), '')
    from public.my_dex();
$$;

select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
select public.start_game();

-- A Charmander egg, full.
reset role;
update public.coder_companions set species_id = 4, is_shiny = false, egg_tokens = 20000000
 where id = pg_temp.main();
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select is(pg_temp.dex(), '', 'an egg is not in the pokedex, since what it holds is hidden');

select public.hatch(pg_temp.main());
select is(pg_temp.dex(), '4', 'hatching writes down what it hatched as');

reset role;
update public.coder_companions set level = 16 where id = pg_temp.main();
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
select public.evolve(pg_temp.main());
select is(pg_temp.dex(), '4 5', 'evolving writes down the new form and keeps the old');

-- A second Charmander, shiny, hatched straight away.
reset role;
insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, gender)
values ('00000000-0000-0000-0000-00000000000a', 4, 'national', true, 'male');
update public.coder_companions set hatched_at = now(), level = 1
 where user_id = '00000000-0000-0000-0000-00000000000a' and hatched_at is null;
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select is(pg_temp.dex(), '4✨ 5', 'a shiny one marks the form shiny, and only that form');
select is((select shiny_front from public.my_dex() where species_id = 4),
  (select sprites ->> 'front_shiny' from public.pokedex_species where id = 4),
  'with its shiny sprite');
select is((select count(*)::int from public.my_dex() where species_id = 5 and shiny_front is null), 1,
  'and none where it was never had shiny');

-- East Sea Shellos, a form of the species whose default is West Sea.
reset role;
insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, gender, hatched_at, level)
select '00000000-0000-0000-0000-00000000000a', id, 'national', false, 'female', null, null
  from public.pokedex_species where slug = 'shellos-east';
update public.coder_companions set hatched_at = now(), level = 1
 where user_id = '00000000-0000-0000-0000-00000000000a' and hatched_at is null;
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select is((select default_id from public.my_dex() d join public.pokedex_species s on s.id = d.species_id
            where s.slug = 'shellos-east'),
  (select form_of from public.pokedex_species where slug = 'shellos-east'),
  'a form names its species'' default, for a list that shows one tile a species');

select pg_temp.as_person('00000000-0000-0000-0000-00000000000b');
select is(pg_temp.dex(), '', 'another person sees none of it');

select throws_ok($$ select * from public.coder_dex_entries $$, '42501', null,
  'and nobody reads the table itself');

reset role;
set local role anon;
select throws_ok($$ select * from public.my_dex() $$, '42501', null, 'a visitor cannot ask');

reset role;
select is((select count(*)::int from public.coder_dex_entries), 3,
  'one row a form, however many times it was had');

select * from finish();
rollback;
