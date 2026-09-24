-- species and the pokedex: reference data anyone may read and nobody may change.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(12);

select is((select count(*)::int from public.species where generation = 1), 151,
  'every Generation I species has its default form');

select is((select count(*)::int from public.pokedex where dex = 'national'), 151, 'the national pokedex lists them');
select is((select count(*)::int from public.pokedex where dex = 'kanto'), 151, 'and so does Kanto''s');

select isnt(
  (select ko_description from public.pokedex where dex = 'national' and number = 6),
  (select ko_description from public.pokedex where dex = 'kanto' and number = 6),
  'each pokedex writes its own entry');

select is(
  (select row(f.slug, m.trigger, m.level, m.item)::text
     from public.species s
     join public.species f on f.id = s.evolves_from_id
     join public.evolution_methods m on m.id = s.evolution_method
    where s.slug = 'raichu'),
  '(pikachu,use-item,,thunder-stone)',
  'an evolution names the row it comes from, and a method: what sets it off, and what it takes');

select is(
  (select i.ko_name from public.evolution_methods m join public.items i on i.id = m.item
    where m.id = 'use-item-thunder-stone'),
  '천둥의돌', 'and the item is named');

select is((select evolution_method from public.species where slug = 'charmeleon'), 'level-up-16',
  'a method is named for what it is, so every Lv.16 evolution shares one');

select is_empty(
  $$ select slug from public.species
      where ko_name is null or en_name is null or ko_genus is null or en_genus is null $$,
  'every form is named and categorised in Korean and English, though a language may be missing');

select is(public.first_form(149), 147, 'Dragonite''s family starts with Dratini');

select is((select category from public.species where slug = 'mewtwo'), 'legendary', 'a category is one of three, or none');

set local role anon;
select throws_ok($$ update public.species set capture_rate = 255 $$, '42501', null,
  'anyone may read it, and nobody may change it');
select throws_ok($$ select * from public.game_species $$, '42501', null,
  'the game''s own tables stay closed to visitors');
reset role;

select * from finish();
rollback;
