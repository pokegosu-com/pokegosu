-- Workplaces, points and the shop.
--
-- now() stands still inside a test's transaction, so every workplace opens
-- and every shift starts at the same moment, and usage written for the hours
-- after it counts for all of them. Workplaces are rolled at random; where a
-- case needs known types, the row is set directly.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(67);

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

-- Usage in hours from the one now falls in: 0 is that hour, 1 the next.
create function pg_temp.work_hours(first integer, last integer) returns void language sql as $$
  insert into public.usage_rollups (user_id, device_id, provider, hour_bucket, tokens)
  select '00000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'claude_code',
         date_trunc('hour', now(), 'UTC') + make_interval(hours => n), 1000
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
-- Every workplace for Rattata, which is Normal.
update public.coder_workplaces set client_id = 19, task_id = 'errands'
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


-- ------------------------------------------------------------
-- Settling and rerolling
-- ------------------------------------------------------------
select is(public.settle(pg_temp.workplace(1)), '{"outcome": "not_ready"}'::jsonb, 'a shift is not done at once');
select is(public.reroll(pg_temp.workplace(2)), '{"outcome": "rerolled"}'::jsonb,
  'a request can be turned down as soon as it is up');
select is(public.work() -> 'workplaces' -> 1,
  jsonb_build_object('id', pg_temp.workplace(2), 'slot', 2, 'arrived', false, 'hours_to_arrive', 8,
                     'client', null, 'task', null, 'types', null, 'can_reroll', false, 'worker', null),
  'and the next one is 8 hours away, saying nothing of who it is from');
select is(public.assign(pg_temp.workplace(2), (select rattata from mon)), '{"outcome": "not_arrived"}'::jsonb,
  'nobody can be sent to it before it arrives');
select is(public.reroll(pg_temp.workplace(2)), '{"outcome": "not_arrived"}'::jsonb, 'nor can it be turned down');

reset role;
select pg_temp.work_hours(1, 7);
select pg_temp.as_person();
select is(public.work() -> 'workplaces' -> 0 -> 'worker' -> 'hours', '7'::jsonb, 'hours are the hours with usage');
select is(public.settle(pg_temp.workplace(1)), '{"outcome": "not_ready"}'::jsonb, 'seven is not a shift');
select is(public.work() -> 'workplaces' -> 1 -> 'hours_to_arrive', '1'::jsonb, 'the next request is an hour away');

reset role;
select pg_temp.work_hours(0, 0);
insert into public.usage_rollups (user_id, device_id, provider, hour_bucket, tokens)
values ('00000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'codex',
        date_trunc('hour', now(), 'UTC'), 5);
select pg_temp.as_person();
select is(public.work() -> 'workplaces' -> 0 -> 'worker' -> 'hours', '8'::jsonb,
  'the hour it was sent in counts, and an hour two agents worked in counts once');
select ok((public.work() -> 'workplaces' -> 0 -> 'worker' ->> 'can_settle')::boolean, 'eight is a shift');
select ok((public.work() -> 'workplaces' -> 1 ->> 'arrived')::boolean, 'and the next request has arrived');
select ok(public.work() -> 'workplaces' -> 1 -> 'client' <> 'null'::jsonb, 'saying who it is from');

select is(public.settle(pg_temp.workplace(1)), '{"outcome": "settled", "points": 160}'::jsonb, 'settling pays the shift');
select is((public.work() ->> 'points')::int, 160, 'into the points');
select is(public.work() -> 'workplaces' -> 0 -> 'worker', 'null'::jsonb, 'and the workplace becomes a new one');
select is(pg_temp.boxed((select machop from mon)) -> 'workplace_id', 'null'::jsonb, 'with its worker back');

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
select is(public.settle_trainer(), '{"outcome": "settled", "hours": 23, "points": 230, "bonus": 1000}'::jsonb,
  'with 1,000 more for reaching 24 hours');


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

select is(public.buy('fire-stone'), '{"outcome": "bought", "points": 36470}'::jsonb, 'a stone is bought with points');
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

reset role;
select lives_ok($$ delete from auth.users where id = '00000000-0000-0000-0000-00000000000a' $$,
  'closing an account takes its workplaces, points and bag with it');

select * from finish();
rollback;
