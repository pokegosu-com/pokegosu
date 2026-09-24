-- The game: an egg, the tokens that fill it, and the buttons after that.
--
-- Usage is written straight into the ledger here; how it gets there is
-- coder's business and its own test's. Where a case needs a known species or
-- a high level, the row is set directly rather than rolled or earned.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(62);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local'),
  ('00000000-0000-0000-0000-00000000000b', 'b@test.local');

insert into public.devices (id, user_id, name, api_key_hash) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a', 'laptop',
   sha256('key-a'::bytea));

create function pg_temp.as_person(id uuid) returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.use(tokens bigint, at timestamptz) returns void language sql as $$
  insert into public.usage_rollups (user_id, device_id, provider, hour_bucket, tokens)
  values ('00000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111',
          'claude_code', at, tokens);
$$;

-- As its owner, since a person cannot read trainers themselves.
create function pg_temp.main() returns uuid language sql security definer as $$
  select main_companion_id from public.coder_trainers where user_id = '00000000-0000-0000-0000-00000000000a';
$$;


-- ------------------------------------------------------------
-- What an egg can hold
-- ------------------------------------------------------------
select is((select count(*)::int from public.coder_egg_species where egg_kind = 'national'), 61,
  'a national egg holds every Generation I family that evolves by level alone, or not at all');
select is((select count(*)::int from public.coder_egg_species where egg_kind = 'gen1'), 61,
  'and a Generation I egg the same, while the pokedex holds no other generation');
select is_empty(
  $$ select g.species_id from public.coder_egg_species g join public.pokedex_species s on s.id = g.species_id
      where s.evolves_from_id is not null or s.slug in ('abra', 'pikachu', 'nidoran-f', 'eevee') $$,
  'only a first form, and none whose family needs a stone or a trade');
select ok((select count(*) = 3 from public.coder_egg_species g join public.pokedex_species s on s.id = g.species_id
            where g.egg_kind = 'national' and s.slug in ('tauros', 'mewtwo', 'ditto')),
  'one that never evolves is in, a legendary and Ditto too');
select results_eq(
  $$ select g.rarity, count(*)::int
       from public.coder_egg_species g
       join public.coder_egg_rarities r on r.id = g.rarity
      where g.egg_kind = 'national'
      group by g.rarity, r.weight
      order by r.weight desc $$,
  $$ values ('common', 11), ('uncommon', 25), ('rare', 12), ('very-rare', 8), ('mythic', 5) $$,
  'every species an egg can hold has a tier');
select is(
  (select string_agg(s.slug || ':' || g.rarity, ' ' order by s.id)
     from public.coder_egg_species g join public.pokedex_species s on s.id = g.species_id
    where g.egg_kind = 'national' and s.slug in ('pidgey', 'charmander', 'omanyte', 'dratini', 'snorlax', 'mewtwo')),
  'charmander:very-rare pidgey:common omanyte:very-rare snorlax:rare dratini:very-rare mewtwo:mythic',
  'the starters, fossils and Dratini are very rare, legendaries mythic');
select is(public.level_up_evolution(148), row(149, 55::smallint)::record,
  'Dragonair becomes Dragonite at Lv.55');
select is((select tokens from public.coder_experience_levels where growth_rate = 'medium' and level = 50),
  200000000::bigint, 'Medium Fast reaches Lv.50 on 200M tokens');
select is((select tokens from public.coder_experience_levels where growth_rate = 'medium' and level = 100),
  500000000::bigint, 'and Lv.100 on 500M, Lv.50 being 40% of it');
select is((select tokens from public.coder_experience_levels where growth_rate = 'slow' and level = 100),
  625000000::bigint, 'a slow one needs a quarter more, as in the games');


-- ------------------------------------------------------------
-- Starting
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select is(public.box(), '{"started": false, "balance": "0"}'::jsonb, 'before starting there is only a balance');

select is(public.start_game() ->> 'outcome', 'started', 'starting hands over an egg');
select is(public.start_game(), '{"outcome": "already_started"}'::jsonb, 'and only once');

select is(jsonb_array_length(public.box() -> 'eggs'), 1, 'the egg is in the egg box');
select is(public.box() -> 'eggs' -> 0 ->> 'id', pg_temp.main()::text, 'and it is the main');
select ok(not (public.box() -> 'eggs' -> 0 ? 'species_id') and not (public.box() -> 'eggs' -> 0 ? 'is_shiny'),
  'an egg does not say what it holds');

select throws_ok($$ select * from public.coder_companions $$, '42501', null,
  'a person cannot read their companions directly, so an egg cannot be looked into');

-- Charmander from here on: 20 cycles, so 20,000,000 tokens; Medium Slow.
reset role;
update public.coder_companions set species_id = 4, is_shiny = false where id = pg_temp.main();


-- ------------------------------------------------------------
-- Claiming into an egg
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select is(public.claim(gen_random_uuid(), 1), '{"outcome": "not_main"}'::jsonb, 'only the main may be fed');
select is(public.claim(pg_temp.main(), 1), '{"outcome": "nothing", "balance": "0"}'::jsonb,
  'with nothing used there is nothing to claim');

reset role;
select pg_temp.use(60000000, '2026-09-23T10:00:00Z');
select pg_temp.use(999, '2026-09-23T11:00:00Z');
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select is(public.claim(pg_temp.main(), 0), '{"outcome": "invalid_amount"}'::jsonb, 'an amount is positive');
select is((public.box() ->> 'balance'), '60000999', 'and a refused one spends nothing');

-- An egg counts tokens as a Pokémon counts experience, whole cycles or not.
select is(public.claim(pg_temp.main(), 1500000),
  '{"outcome": "claimed", "tokens": 1500000, "level_before": null, "level_after": null, "balance": "58500999"}'::jsonb,
  'an egg takes tokens, not cycles');

select is(public.claim(pg_temp.main(), 90000000),
  '{"outcome": "claimed", "tokens": 18500000, "level_before": null, "level_after": null, "balance": "40000999"}'::jsonb,
  'more than an egg needs is cut to what it needs');

select is(public.claim(pg_temp.main(), 1000000), '{"outcome": "nothing", "balance": "40000999"}'::jsonb,
  'a full egg takes nothing until it hatches');

select is(public.box() -> 'eggs' -> 0 -> 'tokens_needed', '20000000'::jsonb,
  'the box says how far it has to go, in tokens: 20 cycles at 1,000,000 each');


-- ------------------------------------------------------------
-- Hatching
-- ------------------------------------------------------------
select is(public.hatch(pg_temp.main()), '{"outcome": "hatched", "species_id": 4, "is_shiny": false}'::jsonb,
  'a full egg hatches when asked');
select is(public.hatch(pg_temp.main()), '{"outcome": "not_an_egg"}'::jsonb, 'and only once');

select is(public.box() -> 'pokemon' -> 0 -> 'level', '1'::jsonb, 'it hatches at Lv.1');
select is(public.box() -> 'pokemon' -> 0 -> 'species_id', '4'::jsonb, 'as what the egg held');
select is(public.box() -> 'eggs', '[]'::jsonb, 'and leaves the egg box');


-- ------------------------------------------------------------
-- Claiming into a Pokémon
-- ------------------------------------------------------------
-- The 40,000,999 left, to the token, is Lv.14 on the game's Medium Slow curve.
select is(public.claim(pg_temp.main(), 999999999),
  '{"outcome": "claimed", "tokens": 40000999, "level_before": 1, "level_after": 14, "balance": "0"}'::jsonb,
  'more than is left is cut to what is left, and a token is a point of experience');

select is((public.box() -> 'pokemon' -> 0 ->> 'level_tokens')::bigint, 37627916::bigint,
  'the box gives where this level starts, from the game''s own curve');
select is((public.box() -> 'pokemon' -> 0 ->> 'next_level_tokens')::bigint, 41442108::bigint, 'and where the next one does');
select is((public.box() -> 'pokemon' -> 0 ->> 'tokens')::bigint, 40000999::bigint, 'and where it stands');
select is(public.box() -> 'pokemon' -> 0 ->> 'growth_rate', 'medium-slow', 'and on which curve, for the screen to count along');
select is((public.box() -> 'pokemon' -> 0 ->> 'max_tokens')::bigint, 529930000::bigint, 'and what Lv.100 takes');
select ok(not (public.box() -> 'pokemon' -> 0 ->> 'can_evolve')::boolean, 'Charmander waits for Lv.16');

reset role;
select pg_temp.use(20000000, '2026-09-23T12:00:00Z');
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
select is(public.claim(pg_temp.main(), 20000000) ->> 'level_after', '19', 'the next day''s tokens take it to Lv.19');
select ok((public.box() -> 'pokemon' -> 0 ->> 'can_evolve')::boolean, 'past Lv.16 it can evolve');


-- ------------------------------------------------------------
-- Evolving
-- ------------------------------------------------------------
select is(public.evolve(pg_temp.main()), '{"outcome": "evolved", "from": 4, "to": 5}'::jsonb,
  'it evolves when asked, not before');
select is(public.evolve(pg_temp.main()), '{"outcome": "not_ready"}'::jsonb, 'Charmeleon waits for Lv.36');
select is(public.box() -> 'pokemon' -> 0 -> 'evolves_to',
  '{"species_id": 6, "ko_name": "리자몽", "en_name": "Charizard", "level": 36}'::jsonb,
  'and the box says what comes next');


-- ------------------------------------------------------------
-- The Lv.50 egg
-- ------------------------------------------------------------
select is(public.receive_egg(pg_temp.main()), '{"outcome": "not_ready"}'::jsonb, 'no egg before Lv.50');

reset role;
update public.coder_companions set level = 50, exp = 211972000 where id = pg_temp.main();
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select ok((public.box() -> 'pokemon' -> 0 ->> 'can_receive_egg')::boolean, 'at Lv.50 the egg is waiting');
select is(public.receive_egg(pg_temp.main()) ->> 'outcome', 'received', 'and is handed over when asked');
select is(public.receive_egg(pg_temp.main()), '{"outcome": "already_received"}'::jsonb, 'once per Pokémon');
select is(jsonb_array_length(public.box() -> 'eggs'), 1, 'the new egg goes to the egg box');


-- ------------------------------------------------------------
-- Main and markings
-- ------------------------------------------------------------
select is(public.set_main((public.box() -> 'eggs' -> 0 ->> 'id')::uuid), '{"outcome": "set"}'::jsonb,
  'any companion can be the main, an egg included');
select ok((public.box() -> 'eggs' -> 0 ->> 'is_main')::boolean, 'and the box says so');

-- ★ red, ● blue.
select is(public.set_markings(pg_temp.main(), (2 << 8 | 1)::smallint), '{"outcome": "set"}'::jsonb,
  'marks are set');
select throws_ok($$ select public.set_markings(pg_temp.main(), 3::smallint) $$, '23514', null,
  'a mark has no fourth state');


-- ------------------------------------------------------------
-- Ribbons
-- ------------------------------------------------------------
reset role;
update public.coder_trainers set main_companion_id = (select id from public.coder_companions where species_id = 5)
 where user_id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

select is(public.receive_ribbon(pg_temp.main(), 'level-100'), '{"outcome": "not_ready"}'::jsonb,
  'the Lv.100 ribbon waits for Lv.100');

reset role;
update public.coder_companions set level = 100, exp = 529930000 where id = pg_temp.main();
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');

reset role;
select pg_temp.use(1000, '2026-09-23T13:00:00Z');
select pg_temp.as_person('00000000-0000-0000-0000-00000000000a');
select is(public.claim(pg_temp.main(), 1000), '{"outcome": "nothing", "balance": "1000"}'::jsonb,
  'a Lv.100 takes no more experience');
select is(public.box() -> 'pokemon' -> 0 -> 'ribbons_waiting' -> 0 ->> 'id', 'level-100', 'the ribbon is waiting');
select is(public.receive_ribbon(pg_temp.main(), 'level-100'), '{"outcome": "received"}'::jsonb, 'and is handed over');
select is(public.receive_ribbon(pg_temp.main(), 'level-100'), '{"outcome": "already_received"}'::jsonb,
  'once per Pokémon');
select is(public.receive_ribbon(pg_temp.main(), 'nope'), '{"outcome": "unknown_ribbon"}'::jsonb,
  'a ribbon that does not exist says so');


-- ------------------------------------------------------------
-- Someone else
-- ------------------------------------------------------------
select pg_temp.as_person('00000000-0000-0000-0000-00000000000b');
select is(public.hatch(pg_temp.main()), '{"outcome": "not_found"}'::jsonb,
  'another person''s companion is not found');
select is(public.claim(pg_temp.main(), 1), '{"outcome": "not_started"}'::jsonb,
  'and nobody else''s tokens reach it');


-- ------------------------------------------------------------
-- Rolling
-- ------------------------------------------------------------
reset role;
select public.roll_egg('00000000-0000-0000-0000-00000000000b', 'gen1') from generate_series(1, 200);
select is_empty(
  $$ select c.id from public.coder_companions c
      where c.user_id = '00000000-0000-0000-0000-00000000000b'
        and (c.egg_kind <> 'gen1'
             or c.species_id not in (select species_id from public.coder_egg_species where egg_kind = 'gen1')) $$,
  'an egg holds only what its kind lists, and remembers its kind');
select throws_ok($$ select public.roll_egg('00000000-0000-0000-0000-00000000000b', 'nope') $$,
  'P0001', null, 'an egg of a kind that holds nothing is refused');

select lives_ok($$ delete from auth.users where id = '00000000-0000-0000-0000-00000000000a' $$,
  'closing an account takes its trainer and companions with it');

select * from finish();
rollback;
