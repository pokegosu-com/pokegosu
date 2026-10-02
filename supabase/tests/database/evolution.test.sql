-- The ways to evolve beyond a level or a stone: friendship, requests, the
-- box, draws, items in place of trades and places, Shedinja, and
-- Generation VIII's.
--
-- now() stands still inside a test's transaction, and the hour it falls in is
-- not known, so a case that hangs on the time of day asks the ways at an
-- hour, not the buttons. Pokémon, bags and requests done are set directly,
-- and the buttons are pressed as the person's claims but the owner's role,
-- which reads the tables a case keeps its Pokémon in.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(45);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local');

create function pg_temp.as_person() returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims',
                    json_build_object('sub', '00000000-0000-0000-0000-00000000000a', 'role', 'authenticated')::text, true);
$$;

create function pg_temp.pokemon(slug text, lvl integer, gender text default 'male') returns uuid language sql as $$
  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, hatched_at, level, gender)
  values ('00000000-0000-0000-0000-00000000000a',
          (select id from public.pokedex_species s where s.slug = pokemon.slug), 'national', false, now(), lvl,
          gender)
  returning id;
$$;

create function pg_temp.give(item text, n integer default 1) returns void language sql as $$
  insert into public.coder_bag (user_id, item_id, quantity) values ('00000000-0000-0000-0000-00000000000a', item, n)
  on conflict (user_id, item_id) do update set quantity = public.coder_bag.quantity + n;
$$;

create function pg_temp.done(companion uuid, client text) returns void language sql as $$
  insert into public.coder_requests_done (user_id, companion_id, client_id)
  values ('00000000-0000-0000-0000-00000000000a', companion,
          (select id from public.pokedex_species s where s.slug = client));
$$;

create function pg_temp.row(id uuid) returns public.coder_companions language sql as $$
  select * from public.coder_companions c where c.id = row.id;
$$;

-- What a Pokémon's ways would make of it at an hour: the first it may take,
-- and the items it may use.
create function pg_temp.next(id uuid, hour integer default 12) returns text language sql as $$
  select s.slug from public.level_up_ways(pg_temp.row(id), hour::smallint) w
    join public.pokedex_species s on s.id = w.id
   where w.ready order by w.priority limit 1;
$$;
create function pg_temp.items(id uuid, hour integer default 12) returns text language sql as $$
  select string_agg(w.item || ':' || s.slug, ' ' order by w.item)
    from public.item_ways(pg_temp.row(id), hour::smallint) w join public.pokedex_species s on s.id = w.id;
$$;

create function pg_temp.slug(id uuid) returns text language sql as $$
  select s.slug from public.coder_companions c join public.pokedex_species s on s.id = c.species_id
   where c.id = slug.id;
$$;

create function pg_temp.boxed(id uuid) returns jsonb language sql as $$
  select p from jsonb_array_elements(public.box() -> 'pokemon') p where p ->> 'id' = id::text;
$$;

select pg_temp.as_person();
select public.start_game();
reset role;
-- The claims stay: auth.uid() is still the person's.


-- ------------------------------------------------------------
-- The person's hour
-- ------------------------------------------------------------
select is(public.local_hour('UTC'), extract(hour from now() at time zone 'UTC')::smallint, 'an hour is the person''s');
select is(public.local_hour('Asia/Seoul'), extract(hour from now() at time zone 'Asia/Seoul')::smallint,
  'in their own time zone');
select is(public.local_hour('Not/AZone'), extract(hour from now() at time zone 'UTC')::smallint,
  'and one Postgres does not know is UTC');
select ok(public.at_time_of_day('day', 6::smallint) and public.at_time_of_day('day', 17::smallint)
          and not public.at_time_of_day('day', 18::smallint),
  'the day runs from 6:00 to 17:59');
select ok(public.at_time_of_day('dusk', 17::smallint) and not public.at_time_of_day('dusk', 18::smallint),
  'dusk is the hour from 17:00');


-- ------------------------------------------------------------
-- Friendship: 4 a level and 15 an hour as the partner, against 160
-- ------------------------------------------------------------
create temporary table mon as
select pg_temp.pokemon('pichu', 25) as pichu, pg_temp.pokemon('eevee', 25) as eevee,
       pg_temp.pokemon('budew', 40) as budew;

select is(pg_temp.next((select pichu from mon)), null, 'Pichu at Lv.25 is not friendly enough');
insert into public.coder_main_periods (companion_id, user_id, started_at, ended_at)
select pichu, '00000000-0000-0000-0000-00000000000a', now() - interval '4 hours', now() from mon;
select is(pg_temp.next((select pichu from mon)), 'pikachu', 'but is after four hours as the partner');

select is(pg_temp.next((select budew from mon), 12) || ' ' || coalesce(pg_temp.next((select budew from mon), 0), '-'),
  'roselia -', 'Budew, friendly at Lv.40, still evolves only by day');

update public.coder_companions set level = 40 where id = (select eevee from mon);
select is(pg_temp.next((select eevee from mon), 12) || ' ' || pg_temp.next((select eevee from mon), 0),
  'espeon umbreon', 'a friendly Eevee becomes Espeon by day and Umbreon by night');
select pg_temp.done((select eevee from mon), 'clefairy');
select is(pg_temp.next((select eevee from mon), 12), 'sylveon',
  'and Sylveon before either, once it has done a Fairy request');


-- ------------------------------------------------------------
-- Requests in place of a move known
-- ------------------------------------------------------------
create temporary table movers as
select pg_temp.pokemon('piloswine', 50) as piloswine, pg_temp.pokemon('poipole', 50, null) as poipole;

select is(pg_temp.next((select piloswine from movers)), null, 'Piloswine needs Ancient Power');
select pg_temp.done((select piloswine from movers), 'charmander');
select is(pg_temp.next((select piloswine from movers)), null, 'which a Fire request does not teach');
select pg_temp.done((select piloswine from movers), 'geodude');
select is(pg_temp.next((select piloswine from movers)), 'mamoswine', 'and a Rock request, one of Geodude''s types, does');
select pg_temp.done((select poipole from movers), 'dratini');
select is(pg_temp.next((select poipole from movers)), 'naganadel', 'Poipole learns Dragon Pulse from a Dragon request');


-- ------------------------------------------------------------
-- The box in place of the party
-- ------------------------------------------------------------
create temporary table party as
select pg_temp.pokemon('pancham', 32) as pancham, pg_temp.pokemon('mantyke', 1) as mantyke;

select is(pg_temp.next((select pancham from party)), null, 'Pancham at Lv.32 needs a Dark type in the box');
select is(pg_temp.next((select mantyke from party)), null, 'and Mantyke a Remoraid');
select pg_temp.pokemon('umbreon', 1), pg_temp.pokemon('remoraid', 1);
select is(pg_temp.next((select pancham from party)) || ' ' || pg_temp.next((select mantyke from party)),
  'pangoro mantine', 'which once there, they evolve');


-- ------------------------------------------------------------
-- Draws
-- ------------------------------------------------------------
create temporary table draws as
select pg_temp.pokemon('tyrogue', 20) as tyrogue, pg_temp.pokemon('beautifly', 10, 'female') as beautifly;

select is(public.owned_line('00000000-0000-0000-0000-00000000000a',
                            (select id from public.pokedex_species where slug = 'silcoon')), 1,
  'a Beautifly counts as a Silcoon line had, for a draw to weigh');

select is(pg_temp.boxed((select tyrogue from draws)) -> 'evolves_to',
  '{"species_id": null, "ko_name": null, "en_name": null, "level": 20, "upside_down": false, "spin": false}'::jsonb,
  'the box says Tyrogue may evolve, not into what');
select ok((public.evolve((select tyrogue from draws)) ->> 'to')::int in (106, 107, 237),
  'and it becomes one of the three');


-- ------------------------------------------------------------
-- Items in place of trades, places, beauty, rain and candy
-- ------------------------------------------------------------
create temporary table holders as
select pg_temp.pokemon('kadabra', 1) as kadabra, pg_temp.pokemon('onix', 1) as onix,
       pg_temp.pokemon('happiny', 1, 'female') as happiny, pg_temp.pokemon('eevee', 1) as eevee,
       pg_temp.pokemon('magneton', 1, null) as magneton, pg_temp.pokemon('feebas', 1) as feebas,
       pg_temp.pokemon('sliggoo', 49) as sliggoo, pg_temp.pokemon('meltan', 1, null) as meltan;

select is(pg_temp.items((select kadabra from holders)), 'linking-cord:alakazam', 'a trade is a Linking Cord');
select is(pg_temp.items((select onix from holders)), 'metal-coat:steelix',
  'and a trade holding an item that item');
select is(pg_temp.items((select happiny from holders), 12) || ' ' || coalesce(pg_temp.items((select happiny from holders), 0), '-'),
  'oval-stone:chansey -', 'an Oval Stone works on Happiny by day only');
select is(pg_temp.items((select eevee from holders)),
  'fire-stone:flareon ice-stone:glaceon leaf-stone:leafeon thunder-stone:jolteon water-stone:vaporeon',
  'a place is a stone, the moss rock a Leaf Stone and the ice rock an Ice Stone');
select is(pg_temp.items((select magneton from holders)), 'thunder-stone:magnezone', 'and a magnetic field a Thunder Stone');
select is(pg_temp.items((select feebas from holders)) || ' ' || pg_temp.items((select meltan from holders)),
  'prism-scale:milotic meltan-candy:melmetal', 'Feebas takes a Prism Scale, and Meltan a Meltan Candy');
select is(pg_temp.items((select sliggoo from holders)), null, 'a Damp Rock waits for Sliggoo''s Lv.50');
update public.coder_companions set level = 50 where id = (select sliggoo from holders);
select is(pg_temp.items((select sliggoo from holders)), 'damp-rock:goodra', 'and then brings the rain');


-- ------------------------------------------------------------
-- Karrablast and Shelmet
-- ------------------------------------------------------------
create temporary table bugs as
select pg_temp.pokemon('shelmet', 1, null) as shelmet;

select pg_temp.give('linking-cord');
select is(public.use_item((select shelmet from bugs), 'linking-cord'), '{"outcome": "no_effect"}'::jsonb,
  'a Linking Cord does nothing to Shelmet with no Karrablast in the box');
alter table bugs add column karrablast uuid;
update bugs set karrablast = pg_temp.pokemon('karrablast', 1);
select is(public.use_item((select shelmet from bugs), 'linking-cord'),
  '{"outcome": "evolved", "from": 616, "to": 617, "received": "shelmet-shell"}'::jsonb,
  'with one, Shelmet becomes Accelgor and leaves its shell');
select is(public.use_item((select karrablast from bugs), 'shelmet-shell'),
  '{"outcome": "evolved", "from": 588, "to": 589}'::jsonb,
  'which makes Karrablast Escavalier');


-- ------------------------------------------------------------
-- Shedinja, and Inkay
-- ------------------------------------------------------------
create temporary table hollow as
select pg_temp.pokemon('nincada', 20) as nincada, pg_temp.pokemon('inkay', 30) as inkay;

create temporary table shed as select public.evolve((select nincada from hollow)) as outcome;
select is(pg_temp.slug((select nincada from hollow)), 'ninjask', 'Nincada becomes Ninjask');
select is(
  (select row(s.slug, c.level, c.exp, c.invested_tokens::bigint, c.egg_tokens)::text
     from public.coder_companions c join public.pokedex_species s on s.id = c.species_id
    where c.id = ((select outcome from shed) ->> 'shed')::uuid),
  '(shedinja,1,0,0,0)', 'and leaves a Lv.1 Shedinja, on no tokens');
select ok(exists (select 1 from public.coder_dex_entries d join public.pokedex_species s on s.id = d.species_id
                   where s.slug = 'shedinja'),
  'which the dex records');

select is(pg_temp.boxed((select inkay from hollow)) ->> 'can_evolve', 'false',
  'Inkay at Lv.30 is not offered as ready');
select is(pg_temp.boxed((select inkay from hollow)) -> 'evolves_to' ->> 'upside_down', 'true',
  'but said to need the screen upside down');
select is(public.evolve((select inkay from hollow)) ->> 'to', '687', 'and evolves when asked');



-- ------------------------------------------------------------
-- Generation VIII
-- ------------------------------------------------------------
create temporary table galar as
select pg_temp.pokemon('toxel', 30) as toxel, pg_temp.pokemon('milcery', 1, 'female') as milcery,
       pg_temp.pokemon('yamask-galar', 50) as yamask, pg_temp.pokemon('farfetchd-galar', 1) as farfetchd,
       pg_temp.pokemon('kubfu', 1) as kubfu, pg_temp.pokemon('applin', 1) as applin,
       pg_temp.pokemon('sinistea-phony', 1, null) as sinistea, pg_temp.pokemon('slowpoke-galar', 1) as slowpoke;

select is(pg_temp.boxed((select toxel from galar)) -> 'evolves_to' ->> 'species_id', null,
  'Toxel''s nature is a draw, so the box names no form');
select ok((public.evolve((select toxel from galar)) ->> 'to')::int in (849, 10343),
  'and it becomes Amped or Low Key Toxtricity');

select is(pg_temp.boxed((select milcery from galar)) -> 'evolves_to' ->> 'spin', 'true',
  'Milcery asks for a spin, by day or night, with no sweet');
select is(pg_temp.boxed((select milcery from galar)) ->> 'can_evolve', 'false',
  'which the screen offers, not the box');
select is(public.evolve((select milcery from galar)) ->> 'to', '869', 'and becomes Alcremie when asked');

select is(pg_temp.next((select yamask from galar)), null, 'Galarian Yamask needs a Ground request');
select pg_temp.done((select yamask from galar), 'sandshrew');
select is(pg_temp.next((select yamask from galar)), 'runerigus', 'after which it becomes Runerigus');

select is(
  pg_temp.items((select farfetchd from galar)) || ' ' || pg_temp.items((select kubfu from galar)) || ' '
    || pg_temp.items((select applin from galar)) || ' ' || pg_temp.items((select sinistea from galar)) || ' '
    || pg_temp.items((select slowpoke from galar)),
  'stick:sirfetchd scroll-of-darkness:urshifu-single-strike scroll-of-waters:urshifu-rapid-strike'
    || ' sweet-apple:appletun tart-apple:flapple cracked-pot:polteageist-phony'
    || ' galarica-cuff:slowbro-galar galarica-wreath:slowking-galar',
  'a Leek in place of three critical hits, scrolls in place of towers, and Galar''s own items');

select * from finish();
rollback;
