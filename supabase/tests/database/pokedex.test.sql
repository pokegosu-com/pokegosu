-- The pokedex_ tables: reference data anyone may read and nobody may change.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(47);

select is((select count(*)::int from public.pokedex_species where generation = 1 and form_of is null), 151,
  'every Generation I species has its default form');
select is((select count(*)::int from public.pokedex_species where generation = 2 and form_of is null), 100,
  'and every Generation II species');
select is((select count(*)::int from public.pokedex_species where generation = 3 and form_of is null), 135,
  'and every Generation III species');
select is((select count(*)::int from public.pokedex_species where generation = 4 and form_of is null), 107,
  'and every Generation IV species');
select is((select count(*)::int from public.pokedex_species where generation = 5 and form_of is null), 156,
  'and every Generation V species');
select is((select count(*)::int from public.pokedex_species where generation = 6 and form_of is null), 72,
  'and every Generation VI species');

select is((select count(*)::int from public.pokedex_species where form_of is not null), 191,
  'and every other form those games had, Mega Evolutions too, but Arceus''s ??? type');

select is((select count(*)::int from public.pokedex_entries where dex = 'national' and is_default), 721, 'the national pokedex lists them');
select is((select count(*)::int from public.pokedex_entries where dex = 'kanto' and is_default), 151, 'Kanto''s the first 151');
select is((select count(*)::int from public.pokedex_entries where dex = 'johto' and is_default), 251, 'Johto''s the first 251, in its own order');
select is((select number from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
            where e.dex = 'johto' and s.slug = 'pikachu'), 22::smallint, 'Pikachu is Johto''s No.22');
select is((select count(*)::int from public.pokedex_entries where dex = 'hoenn' and is_default), 202,
  'and Hoenn''s 202, from Generation III and before');
select is((select count(*)::int from public.pokedex_entries where dex = 'sinnoh' and is_default), 217,
  'and Platinum''s 210, from Generation IV and before, with the 7 legendaries and mythicals it leaves out after them');
select is((select number from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
            where e.dex = 'sinnoh' and s.slug = 'arceus-normal'), 217::smallint, 'Arceus is Sinnoh''s last, No.217');
select is((select count(*)::int from public.pokedex_entries where dex = 'unova' and is_default), 301,
  'and Black 2 and White 2''s 301, from Generation V and before');
select is((select number from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
            where e.dex = 'unova' and s.slug = 'victini'), 0::smallint, 'Victini is Unova''s No.0');
select is((select count(*)::int from public.pokedex_entries where dex = 'kalos' and is_default), 457,
  'and X and Y''s 454, Central, Coastal and Mountain together, with the 3 mythicals they leave out after them');
select is(
  (select string_agg(s.slug || ':' || e.number, ' ' order by e.number)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'kalos' and e.is_default and e.number in (1, 151, 304, 454, 457)),
  'chespin:1 drifloon:151 diglett:304 mewtwo:454 volcanion:457',
  'Coastal numbers on from Central, and Mountain from Coastal');
select is(
  (select count(*)::int from public.pokedex_species s
    where s.form_of is null
      and not exists (select 1 from public.pokedex_entries e
                       where e.species_id = s.id
                         and e.dex = (array['kanto', 'johto', 'hoenn', 'sinnoh', 'unova', 'kalos'])[s.generation])),
  0, 'every species is in its own generation''s regional pokedex');

select isnt(
  (select ko_description from public.pokedex_entries where dex = 'national' and number = 6 and is_default),
  (select ko_description from public.pokedex_entries where dex = 'kanto' and number = 6 and is_default),
  'each pokedex writes its own entry');

select is(
  (select row(f.slug, m.trigger, m.level, m.item)::text
     from public.pokedex_species s
     join public.pokedex_species f on f.id = s.evolves_from_id
     join public.pokedex_evolution_methods m on m.id = s.evolution_method
    where s.slug = 'raichu'),
  '(pikachu,use-item,,thunder-stone)',
  'an evolution names the row it comes from, and a method: what sets it off, and what it takes');

select is(
  (select i.ko_name from public.pokedex_evolution_methods m join public.pokedex_items i on i.id = m.item
    where m.id = 'use-item-thunder-stone'),
  '천둥의돌', 'and the item is named');

select is((select evolution_method from public.pokedex_species where slug = 'charmeleon'), 'level-up-16',
  'a method is named for what it is, so every Lv.16 evolution shares one');

select is_empty(
  $$ select slug from public.pokedex_species
      where ko_name is null or en_name is null or ko_genus is null or en_genus is null $$,
  'every form is named and categorised in Korean and English, though a language may be missing');

select is(public.pokedex_first_form(149), 147, 'Dragonite''s family starts with Dratini');
select is(public.pokedex_first_form(26), 172, 'and Raichu''s with Pichu, from the generation after');

select is(
  (select row(f.slug, m.trigger, m.level, m.held_item, m.min_happiness, m.time_of_day, m.relative_physical_stats)::text
     from public.pokedex_species s
     join public.pokedex_species f on f.id = s.evolves_from_id
     join public.pokedex_evolution_methods m on m.id = s.evolution_method
    where s.slug = 'hitmonchan'),
  '(tyrogue,level-up,20,,,,-1)',
  'a method keeps what Generation II adds: Attack against Defense');
select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s where s.slug in ('steelix', 'umbreon', 'crobat')),
  'crobat:level-up-happiness-160 umbreon:level-up-happiness-160-night steelix:trade-holding-metal-coat',
  'an item held in a trade, friendship, and the time of day');

select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s where s.slug in ('silcoon', 'cascoon', 'milotic', 'shedinja')),
  'silcoon:level-up-7-chance-50 cascoon:level-up-7-chance-50 shedinja:shed milotic:level-up-beauty-170',
  'a method keeps what Generation III adds: a share by personality, beauty, and shedding');
select is(public.pokedex_first_form(184), 298, 'Azumarill''s family starts with Azurill, from Generation III');

select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s
    where s.slug in ('gallade', 'mothim-plant', 'ambipom', 'magnezone', 'mantine', 'wormadam-plant')),
  'mantine:level-up-with-remoraid wormadam-plant:level-up-20-female mothim-plant:level-up-20-male'
    || ' ambipom:level-up-knowing-double-hit magnezone:level-up-at-mt-coronet gallade:use-item-dawn-stone-male',
  'a method keeps what Generation IV adds: a gender, a move, a place, and a party');
select is((select evolves_from_id from public.pokedex_species where slug = 'manaphy'), null,
  'Phione shares Manaphy''s chain, but never becomes it');
select is(public.pokedex_first_form(143), 446, 'Snorlax''s family starts with Munchlax, from Generation IV');
select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s where s.slug in ('escavalier', 'accelgor')),
  'escavalier:trade-for-shelmet accelgor:trade-for-karrablast',
  'a method keeps what Generation V adds: trading for a given species');
select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s where s.slug in ('pangoro', 'malamar', 'sylveon', 'goodra')),
  'pangoro:level-up-32-with-dark-type malamar:level-up-30-upside-down'
    || ' sylveon:level-up-knowing-fairy-move-affection-2 goodra:level-up-50-in-rain',
  'a method keeps what Generation VI adds: a type in the party, a move''s type, affection, rain and upside down');
select is(
  (select string_agg(s.slug || ':' || coalesce(f.slug, '-') || ':' || coalesce(s.evolution_method, '-'), ' ' order by s.id)
     from public.pokedex_species s left join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('meowstic-male', 'meowstic-female', 'vivillon-meadow', 'vivillon-polar')),
  'vivillon-meadow:spewpa-icy-snow:level-up-12 meowstic-male:espurr:level-up-25-male'
    || ' vivillon-polar:-:- meowstic-female:espurr:level-up-25-female',
  'a female Espurr becomes a female Meowstic, and Spewpa the default Vivillon alone');
select is(
  (select string_agg(s.slug || ':' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('charizard-mega-x', 'kyogre-primal', 'rayquaza-mega')),
  'charizard-mega-x:charizard:mega-evolution-holding-charizardite-x'
    || ' kyogre-primal:kyogre:primal-reversion-holding-blue-orb'
    || ' rayquaza-mega:rayquaza:mega-evolution-knowing-dragon-ascent',
  'a Mega Evolution or Primal Reversion is a stage after its default form, on what it holds or knows');

select is(
  (select string_agg(s.slug || ':' || e.is_default, ' ' order by s.id)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'national' and e.number = 479),
  'rotom:true rotom-heat:false rotom-wash:false rotom-frost:false rotom-fan:false rotom-mow:false',
  'a number lists every form of its species, and shows the default');
select is(
  (select row(ko_name, ko_form_name, en_form_name, form_of, type1, type2)::text
     from public.pokedex_species where slug = 'rotom-heat'),
  '(로토무,히트로토무,"Heat Rotom",479,electric,fire)',
  'a form keeps its species'' name, has one of its own, and its own types');
select is(
  (select row(ko_form_name, form_of, type1)::text from public.pokedex_species where slug = 'arceus-fire'),
  '(불꽃타입,493,fire)',
  'and is named in Korean where PokéAPI names it only in English');
select is(
  (select string_agg(slug || ':' || coalesce(ko_form_name, '-'), ' ' order by id)
     from public.pokedex_species where slug in ('pikachu', 'pichu', 'unown-a', 'unown-question')),
  'pikachu:- pichu:- unown-a:A unown-question:?',
  'a species with one form names none, and neither does a default form the games leave unnamed');
select is(
  (select string_agg(s.slug || '<' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('gastrodon-east', 'wormadam-sandy', 'gastrodon-west')),
  'gastrodon-west<shellos-west:level-up-30 wormadam-sandy<burmy-sandy:level-up-20-female gastrodon-east<shellos-east:level-up-30',
  'a form evolves from the form of the same name');
select is(
  (select count(*)::int from public.pokedex_species
    where slug in ('cherrim-sunshine', 'rotom-heat', 'pichu-spiky-eared') and evolves_from_id is not null),
  0, 'and from nothing where the form before has no such form');

select is(
  (select string_agg(slug || ':' || (sprites ? 'front_female'), ' ' order by id)
     from public.pokedex_species where slug in ('pikachu', 'nidoran-f', 'combee')),
  'pikachu:true nidoran-f:false combee:true',
  'a female that looks different has a sprite of her own');

select is((select category from public.pokedex_species where slug = 'mewtwo'), 'legendary', 'a category is one of three, or none');

set local role anon;
select throws_ok($$ update public.pokedex_species set capture_rate = 255 $$, '42501', null,
  'anyone may read it, and nobody may change it');
select throws_ok($$ select * from public.coder_egg_species $$, '42501', null,
  'the game''s own tables stay closed to visitors');
reset role;

select * from finish();
rollback;
