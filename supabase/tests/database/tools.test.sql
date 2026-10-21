-- Moomoo Milk and balls, used up on requests.
--
-- now() stands still inside a test's transaction, so a shift is started 40
-- hours back and usage written for the hours after that, as in the
-- workplaces test. Whether a client gives an egg is drawn at random, so a
-- ball is tested by handing over balls until one does, and the odds by
-- drawing them many times.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(33);

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

create function pg_temp.workplace(n integer) returns uuid language sql security definer as $$
  select id from public.coder_workplaces
   where user_id = '00000000-0000-0000-0000-00000000000a' and slot = n;
$$;

create function pg_temp.place(n integer) returns jsonb language sql as $$
  select w from jsonb_array_elements(public.work() -> 'workplaces') w where w ->> 'id' = pg_temp.workplace(n)::text;
$$;

create function pg_temp.bag(item text) returns integer language sql security definer as $$
  select coalesce((select quantity from public.coder_bag
                    where user_id = '00000000-0000-0000-0000-00000000000a' and item_id = item), 0);
$$;

create function pg_temp.request_egg() returns uuid language sql security definer as $$
  select id from public.coder_companions
   where user_id = '00000000-0000-0000-0000-00000000000a' and egg_kind = 'request';
$$;

select pg_temp.as_person();
select public.start_game();
reset role;

-- Three active hours, 40 to 38 hours ago, all over.
insert into public.usage_rollups (user_id, device_id, provider, hour_bucket, tokens)
select '00000000-0000-0000-0000-00000000000a', '11111111-1111-1111-1111-111111111111', 'claude_code',
       date_trunc('hour', now(), 'UTC') + make_interval(hours => n - 40), 1000
  from generate_series(0, 2) n;

-- Machop, Fighting, on a Normal request three hours in; the rest empty, and
-- the second for Gyarados, shiny.
update public.coder_workplaces set client_id = 19, task_id = 'errands', is_shiny = false, emptied_at = null
 where user_id = '00000000-0000-0000-0000-00000000000a';
with c as (
  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, hatched_at, level)
  values ('00000000-0000-0000-0000-00000000000a', 66, 'national', false, now(), 50)
  returning id
)
update public.coder_workplaces w
   set companion_id = c.id, assigned_at = now() - interval '40 hours'
  from c
 where w.slot = 1 and w.user_id = '00000000-0000-0000-0000-00000000000a';
update public.coder_workplaces set client_id = 130, is_shiny = true
 where slot = 2 and user_id = '00000000-0000-0000-0000-00000000000a';
insert into public.coder_point_entries (user_id, points, reason)
values ('00000000-0000-0000-0000-00000000000a', 100000, 'bonus');
select pg_temp.as_person();


-- ------------------------------------------------------------
-- The shop
-- ------------------------------------------------------------
select set_eq(
  $$ select id || ' ' || price from public.coder_shop_items where for_requests $$,
  array['poke-ball 200', 'great-ball 600', 'ultra-ball 1200', 'moomoo-milk 40'],
  'the shop sells three balls and Moomoo Milk for requests');
select is(public.work() -> 'tools' -> 'milk' ->> 'quantity', '0', 'work() says how much milk there is');
select is((select jsonb_agg(b ->> 'id') from jsonb_array_elements(public.work() -> 'tools' -> 'balls') b),
  '["poke-ball", "great-ball", "ultra-ball"]'::jsonb, 'and every ball, the commonest first');


-- ------------------------------------------------------------
-- Moomoo Milk
-- ------------------------------------------------------------
select is(public.use_milk(pg_temp.workplace(1)), '{"outcome": "no_milk"}'::jsonb, 'milk has to be bought first');
select public.buy('moomoo-milk');
select is(public.use_milk(pg_temp.workplace(3)), '{"outcome": "empty"}'::jsonb,
  'it is for a Pokémon at work');
select is(pg_temp.bag('moomoo-milk'), 1, 'and is not spent on nobody');
select is(public.use_milk(pg_temp.workplace(1)), '{"outcome": "drunk", "hours_left": 3}'::jsonb,
  'it takes two hours off: eight, less three worked and two drunk, leaves three');
select is(pg_temp.bag('moomoo-milk'), 0, 'and is used up');
select is(pg_temp.place(1) -> 'milk_hours', '2'::jsonb, 'work() says what the milk took off');
select is(pg_temp.place(1) -> 'worker' -> 'hours', '3'::jsonb, 'beside the hours worked');
select is(public.settle(pg_temp.workplace(1)), '{"outcome": "not_ready"}'::jsonb, 'five of eight is not a shift');

select public.buy('moomoo-milk');
select public.buy('moomoo-milk');
select public.buy('moomoo-milk');
select is(public.use_milk(pg_temp.workplace(1)), '{"outcome": "drunk", "hours_left": 1}'::jsonb,
  'milk can be given again and again');
select is(public.use_milk(pg_temp.workplace(1)), '{"outcome": "drunk", "hours_left": 0}'::jsonb,
  'with one hour left it ends the shift, the other hour lost');
select is(pg_temp.place(1) -> 'milk_hours', '5'::jsonb, 'so it took only the one');
select ok((pg_temp.place(1) -> 'worker' ->> 'can_settle')::boolean, 'and the request is done');
select is(public.use_milk(pg_temp.workplace(1)), '{"outcome": "done"}'::jsonb, 'when done, there is no more to drink');
select is(pg_temp.bag('moomoo-milk'), 1, 'and the milk stays in the bag');
select is(public.settle(pg_temp.workplace(1)) ->> 'points', '160', 'the pay is a whole shift');
select is(pg_temp.place(1) -> 'milk_hours', '0'::jsonb, 'the next client starts without milk');


-- ------------------------------------------------------------
-- Balls
-- ------------------------------------------------------------
select is(public.give_ball(pg_temp.workplace(2), 'fire-stone'), '{"outcome": "not_a_ball"}'::jsonb,
  'only a ball is handed over');
select is(public.give_ball(pg_temp.workplace(2), 'ultra-ball'), '{"outcome": "no_ball"}'::jsonb,
  'and only one in the bag');

reset role;
insert into public.coder_bag (user_id, item_id, quantity)
values ('00000000-0000-0000-0000-00000000000a', 'ultra-ball', 100);
select pg_temp.as_person();

-- Gyarados gives an egg in an Ultra Ball one time in five, so a hundred
-- leave it a chance in five billion of giving none.
create temporary table tries as
select n, public.give_ball(pg_temp.workplace(2), 'ultra-ball') ->> 'outcome' as outcome
  from generate_series(1, 100) n;

select is((select count(*)::int from tries where outcome = 'egg'), 1, 'a client gives one egg');
select ok((select bool_and(outcome = 'hesitated') from tries
            where n < (select n from tries where outcome = 'egg')), 'hesitating until it does');
select ok((select bool_and(outcome = 'already_gave') from tries
            where n > (select n from tries where outcome = 'egg')), 'and gives no more after');
select is(pg_temp.bag('ultra-ball'), 100 - (select n::int from tries where outcome = 'egg'),
  'every ball handed over is spent, whatever came of it');
select ok((pg_temp.place(2) ->> 'gave_egg')::boolean, 'work() says the client has given its egg');

reset role;
select results_eq(
  $$ select species_id, egg_kind, is_shiny, ball, egg_from, hatched_at is null
       from public.coder_companions
      where user_id = '00000000-0000-0000-0000-00000000000a' and egg_kind = 'request' $$,
  $$ values (129, 'request', true, 'ultra-ball', 130, true) $$,
  'the egg holds Magikarp, first of the line, shiny as Gyarados, in the Ultra Ball');
select pg_temp.as_person();

select is(public.companion_history(pg_temp.request_egg()) -> 'egg_from' ->> 'ko_name', '갸라도스',
  'its record says who gave it');
select is(
  (select p -> 'ball' ->> 'id' from jsonb_array_elements(public.box() -> 'pokemon') p where (p ->> 'species_id')::int = 66),
  'poke-ball', 'a Pokémon from before is in a Poké Ball');

select public.reroll(pg_temp.workplace(3));
select is(public.give_ball(pg_temp.workplace(3), 'ultra-ball'), '{"outcome": "not_arrived"}'::jsonb,
  'there is nobody to hand a ball to before the next client comes');


-- ------------------------------------------------------------
-- The odds, as the games have them
-- ------------------------------------------------------------
reset role;
select ok((select avg(public.client_gives_egg(130, 'poke-ball')::int) from generate_series(1, 4000))
            between 0.09 and 0.15,
  'Gyarados, at a capture rate of 45, gives one for a Poké Ball about one time in eight');
select ok((select avg(public.client_gives_egg(129, 'poke-ball')::int) from generate_series(1, 4000))
            between 0.40 and 0.48,
  'Magikarp, at 255, nearly one time in two');
select ok((select avg(public.client_gives_egg(130, 'great-ball')::int) from generate_series(1, 4000))
            > (select avg(public.client_gives_egg(130, 'poke-ball')::int) from generate_series(1, 4000)),
  'and a better ball does better');

select * from finish();
rollback;
