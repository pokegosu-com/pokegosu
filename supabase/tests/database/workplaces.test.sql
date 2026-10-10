-- Workplaces, points and the shop.
--
-- now() stands still inside a test's transaction, so every workplace opens
-- and every shift starts at the same moment. An hour only counts once it is
-- over, so once things have started they are moved back 40 hours, and usage
-- is written for the hours after that moment. Workplaces are rolled at random; where a
-- case needs known types, the row is set directly.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(107);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'a@test.local');

insert into public.devices (id, user_id, name, api_key_hash) values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-00000000000a', 'laptop',
   sha256('key-a'::bytea));

create function pg_temp.as_person() returns void language sql as $$
  select set_config('role', 'authenticated', true),
         set_config('request.jwt.claims',
                    json_build_object('sub', '00000000-0000-0000-0000-00000000000a', 'role', 'authenticated')::text, true);
$$;

-- Usage in hours from the one things started in, 40 hours ago: 0 is that
-- hour, 1 the next.
create function pg_temp.work_hours(first integer, last integer) returns void language sql as $$
  insert into public.usage_rollups (user_id, device_id, provider, hour_bucket, tokens)
  select '00000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'claude_code',
         date_trunc('hour', now(), 'UTC') + make_interval(hours => n - 40), 1000
    from generate_series(first, last) n;
$$;

create function pg_temp.workplace(n integer) returns uuid language sql security definer as $$
  select id from public.coder_workplaces
   where user_id = '00000000-0000-0000-0000-00000000000a' and slot = n;
$$;

create function pg_temp.pokemon(species integer, lvl integer) returns uuid language sql as $$
  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, hatched_at, level)
  values ('00000000-0000-0000-0000-00000000000a', species, 'national', false, now(), lvl)
  returning id;
$$;

-- One Pokémon out of work() or box().
create function pg_temp.working(id uuid) returns jsonb language sql as $$
  select p from jsonb_array_elements(public.work() -> 'pokemon') p where p ->> 'id' = id::text;
$$;
create function pg_temp.boxed(id uuid) returns jsonb language sql as $$
  select p from jsonb_array_elements(public.box() -> 'pokemon') p where p ->> 'id' = id::text;
$$;


-- ------------------------------------------------------------
-- The type chart, and what it makes of a workplace
-- ------------------------------------------------------------
select is((select count(*)::int from public.pokedex_type_efficacy), 324, 'every pair of the 18 types has a row');
select results_eq(
  $$ select distinct count(*)::int from public.coder_request_tasks group by type $$,
  $$ values (5) $$,
  'every type has five tasks');
select is((select count(distinct type)::int from public.coder_request_tasks), 18, 'every one of the 18');
select is((select damage_factor from public.pokedex_type_efficacy
            where attacking_type = 'fighting' and defending_type = 'normal'), 200::smallint,
  'Fighting is super effective on Normal');
select is((select damage_factor from public.pokedex_type_efficacy
            where attacking_type = 'normal' and defending_type = 'ghost'), 0::smallint,
  'and Normal does nothing to Ghost');

-- Machop is Fighting, Rattata Normal, Gastly Ghost and Poison.
select is(public.aptitude(66, 'normal', null), 2.0, 'Machop suits a Normal workplace');
select is(public.aptitude(66, 'normal', 'rock'), 4.0, 'and one wanting Normal and Rock twice over');
select is(public.aptitude(19, 'ghost', null), 0.0, 'Rattata knows nothing of a Ghost one');
select is(public.aptitude(19, 'rock', 'steel'), 0.25, 'and little of Rock and Steel');
select is(public.aptitude(92, 'normal', null), 1.0, 'Gastly works with whichever of its types does better');

select is(public.shift_pay(66, 50::smallint, 'normal', null), 160, 'a shift is 8 hours at 10 points, times the aptitude');
select is(public.shift_pay(66, 100::smallint, 'normal', null), 320, 'twice that at Lv.100');
select is(public.shift_pay(66, 75::smallint, 'normal', null), 240, 'and in between on a line');
select is(public.shift_pay(19, 73::smallint, 'rock', 'steel'), 29, 'rounded down once, at the end');


-- ------------------------------------------------------------
-- Starting opens the workplaces
-- ------------------------------------------------------------
select pg_temp.as_person();
select is(public.work(), '{"started": false}'::jsonb, 'before starting there is no work');
select public.start_game();

select is(jsonb_array_length(public.work() -> 'workplaces'), 5, 'starting opens five workplaces');
select ok(
  (select bool_and(w -> 'types' = (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                                    order by t.id = s.type2)
                                     from public.pokedex_species s
                                     join public.pokedex_types t on t.id in (s.type1, s.type2)
                                    where s.id = (w -> 'client' ->> 'species_id')::int
                                    group by s.id))
     from jsonb_array_elements(public.work() -> 'workplaces') w),
  'each wants the types of the Pokémon it is for');
select ok(
  (select bool_and(exists (select 1 from public.coder_request_tasks t join public.pokedex_species k
                                  on t.type in (k.type1, k.type2)
                            where k.id = (w -> 'client' ->> 'species_id')::int and t.id = w -> 'task' ->> 'id'))
     from jsonb_array_elements(public.work() -> 'workplaces') w),
  'and asks for help with a task of one of them');
select is((public.work() ->> 'points')::int, 0, 'with no points yet');
select is(public.work() -> 'pokemon', '[]'::jsonb, 'and nobody to send, with only an egg');
select ok(
  (select bool_and(jsonb_array_length(w -> 'types') between 1 and 2)
     from jsonb_array_elements(public.work() -> 'workplaces') w),
  'each wants one type or two');
select throws_ok($$ select * from public.coder_workplaces $$, '42501', null,
  'a person reads their workplaces through work() only');

reset role;
-- Every workplace for Rattata, which is Normal, and none shiny, so every
-- shift is a whole one.
update public.coder_workplaces set client_id = 19, task_id = 'errands', is_shiny = false
 where user_id = '00000000-0000-0000-0000-00000000000a';
create temporary table mon as
select pg_temp.pokemon(66, 49) as machop, pg_temp.pokemon(19, 50) as rattata;
grant select on mon to authenticated;
select pg_temp.as_person();


-- ------------------------------------------------------------
-- Sending a Pokémon
-- ------------------------------------------------------------
select is(public.assign(pg_temp.workplace(1), (select machop from mon)), '{"outcome": "too_low"}'::jsonb,
  'a Pokémon under Lv.50 cannot work');
select is(jsonb_array_length(public.work() -> 'pokemon'), 1, 'and is not offered');

reset role;
update public.coder_companions set level = 50 where id = (select machop from mon);
select pg_temp.as_person();

select is(pg_temp.working((select machop from mon)) -> 'offers' -> 0,
  jsonb_build_object('workplace_id', pg_temp.workplace(1), 'aptitude', 2.0, 'points', 160),
  'each Pokémon comes with what each workplace would pay it');
select is(public.assign(pg_temp.workplace(1), (select machop from mon)), '{"outcome": "assigned"}'::jsonb,
  'at Lv.50 it can go');
select is(public.assign(pg_temp.workplace(1), (select rattata from mon)), '{"outcome": "occupied"}'::jsonb,
  'one Pokémon to a workplace');
select is(public.assign(pg_temp.workplace(2), (select machop from mon)), '{"outcome": "working"}'::jsonb,
  'and stays there: it cannot be sent elsewhere halfway');
select is(pg_temp.boxed((select machop from mon)) ->> 'workplace_id', pg_temp.workplace(1)::text,
  'the box says where it is');

reset role;
create temporary table egg as
select main_companion_id as id from public.coder_trainers where user_id = '00000000-0000-0000-0000-00000000000a';
grant select on egg to authenticated;
select pg_temp.as_person();

select is(public.set_main((select machop from mon)), '{"outcome": "working"}'::jsonb,
  'a Pokémon out on a request cannot become the partner');
select is(public.evolve((select machop from mon)), '{"outcome": "working"}'::jsonb,
  'nor can it evolve');
select is(public.use_item((select machop from mon), 'fire-stone'), '{"outcome": "working"}'::jsonb,
  'or be given an item');
select is(public.receive_egg((select machop from mon)), '{"outcome": "working"}'::jsonb,
  'or give its egg');
select is(public.receive_ribbon((select machop from mon), 'level-100'), '{"outcome": "working"}'::jsonb,
  'or take a ribbon');
select is(public.set_markings((select machop from mon), 1::smallint), '{"outcome": "working"}'::jsonb,
  'or be marked, until it is back');
select is(public.set_main((select rattata from mon)), '{"outcome": "set"}'::jsonb, 'one at home can');
select ok((pg_temp.working((select rattata from mon)) ->> 'is_main')::boolean, 'and work() says which is the partner');
select is(public.assign(pg_temp.workplace(2), (select rattata from mon)), '{"outcome": "partner"}'::jsonb,
  'the partner stays home');
select public.set_main((select id from egg));


-- ------------------------------------------------------------
-- Settling and rerolling
-- ------------------------------------------------------------
select is(public.settle(pg_temp.workplace(1)), '{"outcome": "not_ready"}'::jsonb, 'a shift is not done at once');
select is(public.reroll(pg_temp.workplace(2)), '{"outcome": "rerolled"}'::jsonb,
  'a request can be turned down as soon as it is up');
select is(public.work() -> 'workplaces' -> 1,
  jsonb_build_object('id', pg_temp.workplace(2), 'slot', 2, 'arrived', false, 'hours_to_arrive', 8,
                     'client', null, 'is_shiny', null, 'shift_hours', null, 'task', null, 'types', null,
                     'can_reroll', false, 'worker', null),
  'and the next one is 8 hours away, saying nothing of who it is from');
select is(public.assign(pg_temp.workplace(2), (select rattata from mon)), '{"outcome": "not_arrived"}'::jsonb,
  'nobody can be sent to it before it arrives');
select is(public.reroll(pg_temp.workplace(2)), '{"outcome": "not_arrived"}'::jsonb, 'nor can it be turned down');

reset role;
insert into public.usage_rollups (user_id, device_id, provider, hour_bucket, tokens)
values ('00000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'claude_code',
        date_trunc('hour', now(), 'UTC'), 1000);
select pg_temp.as_person();
select is(public.work() -> 'workplaces' -> 0 -> 'worker' -> 'hours', '0'::jsonb,
  'a Pokémon starts at 0 hours, though there was usage in the hour it was sent in');

reset role;
update public.coder_trainers set work_started_at = work_started_at - interval '40 hours'
 where user_id = '00000000-0000-0000-0000-00000000000a';
update public.coder_workplaces set assigned_at = assigned_at - interval '40 hours',
                                   emptied_at = emptied_at - interval '40 hours'
 where user_id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.work_hours(1, 7);
select pg_temp.as_person();
select is(public.work() -> 'workplaces' -> 0 -> 'worker' -> 'hours', '7'::jsonb, 'hours are the hours with usage');
select is(public.settle(pg_temp.workplace(1)), '{"outcome": "not_ready"}'::jsonb, 'seven is not a shift');
select is(public.work() -> 'workplaces' -> 1 -> 'hours_to_arrive', '1'::jsonb, 'the next request is an hour away');

reset role;
select pg_temp.work_hours(0, 0);
insert into public.usage_rollups (user_id, device_id, provider, hour_bucket, tokens)
values ('00000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'codex',
        date_trunc('hour', now(), 'UTC') - interval '40 hours', 5);
select pg_temp.as_person();
select is(public.work() -> 'workplaces' -> 0 -> 'worker' -> 'hours', '8'::jsonb,
  'the hour it was sent in counts once over, and an hour two agents worked in counts once');
select ok((public.work() -> 'workplaces' -> 0 -> 'worker' ->> 'can_settle')::boolean, 'eight is a shift');
select ok((public.work() -> 'workplaces' -> 1 ->> 'arrived')::boolean, 'and the next request has arrived');
select ok(public.work() -> 'workplaces' -> 1 -> 'client' <> 'null'::jsonb, 'saying who it is from');

select is(public.settle(pg_temp.workplace(1)), '{"outcome": "settled", "points": 160, "family": 0, "line": null}'::jsonb, 'settling pays the shift');
select is((public.work() ->> 'points')::int, 160, 'into the points');
select is(public.work() -> 'workplaces' -> 0 -> 'worker', 'null'::jsonb, 'and the workplace becomes a new one');
select is(pg_temp.boxed((select machop from mon)) -> 'workplace_id', 'null'::jsonb, 'with its worker back');
reset role;
select is((select string_agg(companion_id || ':' || client_id, ' ') from public.coder_requests_done),
  (select machop from mon) || ':19', 'which keeps the request as one it did, for Rattata');
select pg_temp.as_person();

select public.assign(pg_temp.workplace(3), (select rattata from mon));
select is(public.reroll(pg_temp.workplace(3)), '{"outcome": "occupied"}'::jsonb, 'but not with someone at it');

reset role;
select ok(
  (select bool_and(exists (select 1 from public.pokedex_entries e
                            where e.dex = 'national' and e.is_default and e.species_id = w.client_id))
     from public.coder_workplaces w where w.user_id = '00000000-0000-0000-0000-00000000000a'),
  'a workplace is for a Pokémon from the national pokedex, in its default form');
select pg_temp.as_person();


-- ------------------------------------------------------------
-- The person's own pay
-- ------------------------------------------------------------
select is(public.work() -> 'trainer',
  '{"name": null, "hours": 8, "hours_paid": 0, "points_waiting": 80, "hours_to_bonus": 16}'::jsonb,
  'the person earns 10 an hour, from when they started');
select is(public.settle_trainer(), '{"outcome": "settled", "hours": 8, "points": 80, "bonus": 0}'::jsonb,
  'paid when asked');
select is(public.settle_trainer(), '{"outcome": "nothing"}'::jsonb, 'and not twice');

reset role;
update public.profiles set username = 'ash', display_name = '지우'
 where id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.as_person();
select is(public.work() -> 'trainer' ->> 'name', '지우', 'the person works under their display name');

reset role;
select pg_temp.work_hours(8, 30);
select pg_temp.as_person();
select is(public.settle_trainer(), '{"outcome": "settled", "hours": 23, "points": 230, "bonus": 500}'::jsonb,
  'with 500 more for reaching 24 hours');


-- ------------------------------------------------------------
-- The shop and the bag
-- ------------------------------------------------------------
select is(public.buy('kanto-egg'), '{"outcome": "not_enough_points"}'::jsonb, 'an egg costs 25,000');
select is(public.buy('fire-stone'), '{"outcome": "not_enough_points"}'::jsonb, 'a stone 5,000');

reset role;
insert into public.coder_point_entries (user_id, points, reason)
values ('00000000-0000-0000-0000-00000000000a', 40000, 'shift');
create temporary table fox as select pg_temp.pokemon(37, 20) as vulpix;
grant select on fox to authenticated;
select pg_temp.as_person();

select is(public.buy('fire-stone'), '{"outcome": "bought", "points": 35970}'::jsonb, 'a stone is bought with points');
select is(public.box() -> 'bag', '[{"id": "fire-stone", "ko_name": "불꽃의돌", "en_name": "Fire Stone",
                                    "sprite": "/sprites/items/fire-stone.png", "quantity": 1}]'::jsonb,
  'and goes in the bag');
select is(public.buy('kanto-egg') ->> 'outcome', 'bought', 'an egg too');
select is(jsonb_array_length(public.box() -> 'eggs'), 2, 'and goes in the box');

select is(public.use_item((select machop from mon), 'fire-stone'), '{"outcome": "no_effect"}'::jsonb,
  'a stone does nothing to what it cannot evolve, and is kept');
select is(public.use_item((select vulpix from fox), 'fire-stone'), '{"outcome": "evolved", "from": 37, "to": 38}'::jsonb,
  'Vulpix evolves with a Fire Stone, at any level');
select is(public.use_item((select vulpix from fox), 'fire-stone'), '{"outcome": "not_in_bag"}'::jsonb,
  'which it used up');


-- ------------------------------------------------------------
-- The Dawn Stone, which asks for a gender
-- ------------------------------------------------------------
reset role;
insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, hatched_at, level, gender)
values ('00000000-0000-0000-0000-00000000000a', 281, 'national', false, now(), 30, 'male'),
       ('00000000-0000-0000-0000-00000000000a', 281, 'national', false, now(), 30, 'female');
create temporary table kirlia as
select (select id from public.coder_companions where species_id = 281 and gender = 'male') as he,
       (select id from public.coder_companions where species_id = 281 and gender = 'female') as she;
grant select on kirlia to authenticated;

select pg_temp.as_person();
select is(pg_temp.boxed((select he from kirlia)) -> 'item_evolutions' -> 0 ->> 'species_id', '475',
  'the box says a male Kirlia takes the Dawn Stone');
select is(pg_temp.boxed((select she from kirlia)) -> 'item_evolutions', '[]'::jsonb, 'and a female one does not');
select is(public.buy('dawn-stone') ->> 'outcome', 'bought', 'the Dawn Stone is sold');
select is(public.use_item((select she from kirlia), 'dawn-stone'), '{"outcome": "no_effect"}'::jsonb,
  'and does nothing to a female Kirlia');
select is(public.use_item((select he from kirlia), 'dawn-stone'), '{"outcome": "evolved", "from": 281, "to": 475}'::jsonb,
  'but makes a male one Gallade');



-- ------------------------------------------------------------
-- The Thunder Stone, which makes Alolan Raichu only in Alola
-- ------------------------------------------------------------
reset role;
-- By id: the Kanto egg bought above may hold a Pikachu too.
insert into public.coder_companions (id, user_id, species_id, egg_kind, is_shiny, hatched_at, level, gender)
values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000a', 25, 'alola', false, now(), 30, 'male'),
       ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-00000000000a', 25, 'kanto', false, now(), 30, 'male');
insert into public.coder_bag (user_id, item_id, quantity)
values ('00000000-0000-0000-0000-00000000000a', 'thunder-stone', 2);
create temporary table pikachu as
select '00000000-0000-0000-0000-0000000000a1'::uuid as alolan,
       '00000000-0000-0000-0000-0000000000a2'::uuid as kantonian;
grant select on pikachu to authenticated;

select pg_temp.as_person();
select is(
  (select jsonb_agg(e ->> 'species_id') from jsonb_array_elements(pg_temp.boxed((select alolan from pikachu)) -> 'item_evolutions') e),
  jsonb_build_array((select id from public.pokedex_species where slug = 'raichu-alola')::text),
  'the box says a Pikachu from an Alola egg takes the Thunder Stone to Alolan Raichu alone');
select is(public.use_item((select alolan from pikachu), 'thunder-stone') ->> 'to',
  (select id from public.pokedex_species where slug = 'raichu-alola')::text,
  'and it becomes Alolan Raichu');
select is(public.use_item((select kantonian from pikachu), 'thunder-stone'),
  '{"outcome": "evolved", "from": 25, "to": 26}'::jsonb,
  'but one from any other egg becomes Raichu');

reset role;

-- ------------------------------------------------------------
-- A gift from the client to a Pokémon of its own line
-- ------------------------------------------------------------
select is(public.line_of(26, 172), 'before', 'Pichu is on Raichu''s line, before it');
select is(public.line_of(26, 26), 'same', 'as is Raichu itself');
select is(public.line_of(172, (select id from public.pokedex_species where slug = 'raichu-mega-x')), 'after',
  'and Mega Raichu X after Pichu');
select is(public.line_of(26, (select id from public.pokedex_species where slug = 'raichu-alola')), null,
  'but not Alolan Raichu, a branch beside it');
select ok(public.line_of(133, 134) = 'after' and public.line_of(133, 136) = 'after', 'Eevee''s line holds every evolution');
select ok(public.line_of(134, 133) = 'before' and public.line_of(134, 135) is null, 'Vaporeon''s holds Eevee alone');

update public.coder_workplaces
   set client_id = 26, emptied_at = null, is_shiny = false,
       companion_id = pg_temp.pokemon(25, 50), assigned_at = now() - interval '40 hours'
 where id = pg_temp.workplace(5);
select pg_temp.as_person();
select is(public.settle(pg_temp.workplace(5)), '{"outcome": "settled", "points": 40, "family": 320, "line": "before"}'::jsonb,
  'Pikachu doing Raichu''s request gets 320 points from Raichu besides its pay');
reset role;
select is((select points from public.coder_point_entries where reason = 'family'), 320,
  'kept apart from the pay');


-- ------------------------------------------------------------
-- A shiny client
--
-- Usage runs through hour 30, 10 hours ago, so a shift started 12 hours ago
-- has 3 hours in it and one started 13 hours ago 4.
-- ------------------------------------------------------------
select is(public.shift_length(false), 8::smallint, 'a shift is 8 hours');
select is(public.shift_length(true), 4::smallint, 'and half that for a shiny client');
select is((select count(*)::int from generate_series(1, 6400) where public.roll_shiny()) between 50 and 160, true,
  'a client is shiny about one time in 64, as an egg');

update public.coder_workplaces
   set client_id = 19, task_id = 'errands', emptied_at = null, is_shiny = true,
       companion_id = pg_temp.pokemon(66, 50), assigned_at = now() - interval '12 hours'
 where id = pg_temp.workplace(4);
select pg_temp.as_person();
select ok((public.work() -> 'workplaces' -> 3 ->> 'is_shiny')::boolean, 'work() says the client is shiny');
select is(public.work() -> 'workplaces' -> 3 -> 'shift_hours', '4'::jsonb, 'and its shift is 4 hours');
select is(public.work() -> 'workplaces' -> 3 -> 'worker' -> 'points', '160'::jsonb, 'paying a whole shift');
select is(public.settle(pg_temp.workplace(4)), '{"outcome": "not_ready"}'::jsonb, 'three hours are not enough');

reset role;
update public.coder_workplaces set assigned_at = assigned_at - interval '1 hour'
 where id = pg_temp.workplace(4);
select pg_temp.as_person();
select ok((public.work() -> 'workplaces' -> 3 -> 'worker' ->> 'can_settle')::boolean, 'four are');
select is(public.work() -> 'workplaces' -> 3 -> 'worker' -> 'hours', '4'::jsonb, 'and the hours stop there');
select is(public.settle(pg_temp.workplace(4)), '{"outcome": "settled", "points": 160, "family": 0, "line": null}'::jsonb,
  'which pays what 8 hours would');
reset role;

-- ------------------------------------------------------------
-- The Shiny Charm
-- ------------------------------------------------------------
select is(public.egg_shiny_odds('00000000-0000-0000-0000-00000000000a'), 64, 'an egg is shiny one time in 64');
insert into public.coder_point_entries (user_id, points, reason)
select '00000000-0000-0000-0000-00000000000a',
       (199999 - public.point_balance('00000000-0000-0000-0000-00000000000a'))::integer, 'shift';
select pg_temp.as_person();
select is(public.buy('shiny-charm'), '{"outcome": "not_enough_points"}'::jsonb, 'the Shiny Charm costs 200,000');

reset role;
insert into public.coder_point_entries (user_id, points, reason)
values ('00000000-0000-0000-0000-00000000000a', 25001, 'shift');
select pg_temp.as_person();
select is(public.buy('shiny-charm'), '{"outcome": "bought", "points": 25000}'::jsonb, 'and is bought with points');
select is(public.box() -> 'bag' -> -1, '{"id": "shiny-charm", "ko_name": "빛나는부적", "en_name": "Shiny Charm",
                                         "sprite": "/sprites/items/shiny-charm.png", "quantity": 1}'::jsonb,
  'it goes in the bag, after the stones');
select is(public.buy('shiny-charm'), '{"outcome": "already_held"}'::jsonb, 'once: a second is not sold');

reset role;
select is(public.egg_shiny_odds('00000000-0000-0000-0000-00000000000a'), 32, 'its holder''s eggs are shiny one time in 32');
update public.coder_settings set charm_shiny_odds = 1;
update public.coder_companions set is_shiny = false where user_id = '00000000-0000-0000-0000-00000000000a';
select pg_temp.as_person();
select is(public.buy('kanto-egg') ->> 'outcome', 'bought', 'an egg bought while holding it');
reset role;
select is((select count(*) from public.coder_companions
            where user_id = '00000000-0000-0000-0000-00000000000a' and is_shiny), 1::bigint,
  'is drawn at the charm''s odds, and the eggs from before it are as they were');

select lives_ok($$ delete from auth.users where id = '00000000-0000-0000-0000-00000000000a' $$,
  'closing an account takes its workplaces, points and bag with it');

select * from finish();
rollback;
