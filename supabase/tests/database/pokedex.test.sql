-- The pokedex: reference data anyone may read and nobody may change.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(9);

select is((select count(*)::int from public.pokedex where is_default and generation = 1), 151,
  'every Generation I species has its default form');

select is_empty(
  $$ select slug from public.pokedex
      where not (names ?& array['ko', 'en', 'ja', 'zh-Hans', 'zh-Hant', 'fr', 'de', 'es', 'it']) $$,
  'every form is named in every language kept');

select is(
  (select jsonb_build_object('from', f.slug, 'evolution', p.evolution - 'item')
     from public.pokedex p join public.pokedex f on f.id = p.evolves_from_id where p.slug = 'raichu'),
  '{"from": "pikachu", "evolution": {"trigger": "use-item"}}'::jsonb,
  'an evolution names the row it comes from and what it takes');

select is((select evolution -> 'item' -> 'names' ->> 'ko' from public.pokedex where slug = 'raichu'), '천둥의돌',
  'and names an item in every language too');

select is((select evolves_from_id from public.pokedex where slug = 'pikachu'), null,
  'an evolution from outside the table, Pichu''s, is left out');

select is((select sprites ->> 'animated' from public.pokedex where slug = 'charizard'), '/sprites/pokemon/6.gif',
  'sprites are paths on pokedex-web');

set local role anon;
select is((select count(*)::int from public.pokedex), 151, 'anyone may read it, signed in or not');
select throws_ok($$ update public.pokedex set capture_rate = 255 $$, '42501', null,
  'and nobody may change it');
select throws_ok($$ select * from public.game_species $$, '42501', null,
  'the game''s own tables stay closed to visitors');
reset role;

select * from finish();
rollback;
