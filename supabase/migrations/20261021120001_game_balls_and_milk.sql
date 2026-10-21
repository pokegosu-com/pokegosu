-- Two things the shop sells to be used up on requests, so points keep a use
-- once the evolution items and eggs are bought.
--
-- A ball is handed to a request's client, at any time while it is on the
-- board. The client may give back an egg in it, as often as the games would
-- have it caught: its capture rate and the ball's bonus, at full HP. The egg
-- holds the first stage of the client's line, shiny if the client is, and the
-- Pokémon that hatches keeps the ball. A client gives one egg; until then it
-- can be handed ball after ball.
--
-- Moomoo Milk has the Pokémon on a request finish milk_hours sooner, as often
-- as there is milk. The pay is a whole shift's, as it always was, so milk is
-- worth its price only where an hour pays well: a 1× request never makes it
-- back.


-- ============================================================
-- The balance of it, beside the rest in coder_settings.
-- ============================================================
alter table public.coder_settings
  -- The active hours one Moomoo Milk takes off a shift.
  add column milk_hours smallint not null default 2 check (milk_hours >= 1);

alter table public.coder_settings
  alter column milk_hours drop default;


-- ============================================================
-- coder_balls: the balls a client can be handed, and each one's bonus in the
-- catch formula, as the games give it.
-- ============================================================
create table public.coder_balls (
  item_id    text primary key references public.pokedex_items,
  catch_rate numeric not null check (catch_rate > 0)
);

insert into public.coder_balls (item_id, catch_rate) values
  ('poke-ball', 1),
  ('great-ball', 1.5),
  ('ultra-ball', 2);


-- ============================================================
-- coder_shop_items.for_requests: used up on a request, so the shop shows it
-- apart from the evolution items. Sold for as many points as the hours they
-- are worth: milk saves two hours, which a 1× request pays 20 to 40 points
-- for, and a ball buys a chance at an egg.
-- ============================================================
alter table public.coder_shop_items
  add column for_requests boolean not null default false,
  add constraint only_an_item_is_for_requests check (not for_requests or item_id is not null);

insert into public.coder_shop_items (id, item_id, egg_kind, price, position, kept, for_requests)
select v.id, v.id, null, v.price, max(s.position) + v.n, false, true
  from public.coder_shop_items s,
       (values ('poke-ball', 200, 1), ('great-ball', 600, 2), ('ultra-ball', 1200, 3),
               ('moomoo-milk', 40, 4)) v (id, price, n)
 group by v.id, v.price, v.n;


-- ============================================================
-- coder_workplaces: the hours milk has taken off the shift there, and
-- whether its client has given an egg. Both start again with a new client.
-- ============================================================
alter table public.coder_workplaces
  add column milk_hours smallint not null default 0 check (milk_hours >= 0),
  add column gave_egg   boolean  not null default false;


-- ============================================================
-- coder_companions: the ball a Pokémon is in, and, for one from a client's
-- egg, that client. Every Pokémon before this hatched in a Poké Ball, as an
-- egg does in the games.
-- ============================================================
alter table public.coder_companions
  add column ball     text    not null default 'poke-ball' references public.pokedex_items,
  add column egg_from integer references public.pokedex_species;

insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('request', '의뢰인의 알', 'Client''s Egg');


-- ============================================================
-- Helpers. None is granted to anyone.
-- ============================================================

-- An egg from a request's client: the first stage of its line, in the form
-- that stage takes, shiny if the client is, in the ball it was handed.
create function public.client_egg(owner uuid, client_id integer, is_shiny boolean, ball text)
returns uuid
language plpgsql
volatile
set search_path = ''
as $$
declare
  drawn integer := public.pokedex_first_form(client_egg.client_id);
  gender text := public.draw_gender(drawn);
  egg uuid;
begin
  if gender = 'female' then
    select coalesce((select s.id from public.pokedex_species s
                      where s.form_of = drawn and s.slug like '%-female'), drawn)
      into drawn;
  end if;

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, gender, ball, egg_from)
  values (owner, drawn, 'request', client_egg.is_shiny, gender, client_egg.ball, client_egg.client_id)
  returning id into egg;
  return egg;
end;
$$;

-- Whether a client handed this ball gives an egg: the games' odds from
-- Generation VI on, at full HP and with no status. a = capture rate × ball ÷ 3,
-- and four shake checks pass together one time in (255 ÷ a)^(3/4).
create function public.client_gives_egg(client_id integer, ball text)
returns boolean
language sql
volatile
set search_path = ''
as $$
  select random() < power(least(255, floor(s.capture_rate * l.catch_rate / 3)) / 255.0, 0.75)
    from public.pokedex_species s, public.coder_balls l
   where s.id = client_gives_egg.client_id and l.item_id = client_gives_egg.ball;
$$;

revoke execute on function public.client_egg(uuid, integer, boolean, text),
                         public.client_gives_egg(integer, text) from public;


-- ============================================================
-- settle — as before, done once the hours worked and the milk drunk make a
-- shift, and the next client starts without either.
-- ============================================================
create or replace function public.settle(workplace_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  place public.coder_workplaces;
  pokemon public.coder_companions;
  pay integer;
  gift integer := 0;
  line text;
  client integer;
begin
  perform public.lock_trainer(caller);
  select * into place from public.coder_workplaces w
   where w.id = settle.workplace_id and w.user_id = caller for update;
  if place.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if place.companion_id is null then
    return jsonb_build_object('outcome', 'empty');
  end if;
  if public.active_hours(caller, place.assigned_at) + place.milk_hours < public.shift_length(place.is_shiny) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  select * into pokemon from public.coder_companions c where c.id = place.companion_id;
  -- A whole shift's pay, however short the shift.
  select public.shift_pay(pokemon.species_id, pokemon.level, k.type1, k.type2) into pay
    from public.pokedex_species k where k.id = place.client_id;
  if pay > 0 then
    insert into public.coder_point_entries (user_id, points, reason) values (caller, pay, 'shift');
  end if;
  line := public.line_of(place.client_id, pokemon.species_id);
  if line is not null then
    select g.family_points into gift from public.coder_settings g;
    if gift > 0 then
      insert into public.coder_point_entries (user_id, points, reason) values (caller, gift, 'family');
    end if;
  end if;
  insert into public.coder_requests_done (user_id, companion_id, client_id)
  values (caller, pokemon.id, place.client_id);

  client := public.roll_client();
  update public.coder_workplaces w
     set client_id = client, task_id = public.roll_task(client), is_shiny = public.roll_shiny(),
         emptied_at = null, companion_id = null, assigned_at = null, milk_hours = 0, gave_egg = false
   where w.id = place.id;
  return jsonb_build_object('outcome', 'settled', 'points', pay, 'family', gift, 'line', line);
end;
$$;


-- ============================================================
-- replace_workplace — as before, the next client starting without milk or
-- an egg given.
-- ============================================================
create or replace function public.replace_workplace(workplace_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  client integer := public.roll_client();
begin
  update public.coder_workplaces w
     set client_id = client, task_id = public.roll_task(client), is_shiny = public.roll_shiny(),
         emptied_at = now(), companion_id = null, assigned_at = null, milk_hours = 0, gave_egg = false
   where w.id = replace_workplace.workplace_id;
end;
$$;


-- ============================================================
-- use_milk — gives the Pokémon on a request a Moomoo Milk, so its shift ends
-- milk_hours sooner. With less left than that, it ends now, and the hours
-- over are lost.
--
--   → {"outcome": "drunk", "hours_left": 3}
--   → {"outcome": "not_found"} | {"outcome": "empty"} | {"outcome": "done"}
--     | {"outcome": "no_milk"}
-- ============================================================
create function public.use_milk(workplace_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  place public.coder_workplaces;
  left_hours integer;
  taken integer;
begin
  perform public.lock_trainer(caller);
  select * into place from public.coder_workplaces w
   where w.id = use_milk.workplace_id and w.user_id = caller for update;
  if place.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if place.companion_id is null then
    return jsonb_build_object('outcome', 'empty');
  end if;
  left_hours := public.shift_length(place.is_shiny) - place.milk_hours
              - public.active_hours(caller, place.assigned_at);
  if left_hours <= 0 then
    return jsonb_build_object('outcome', 'done');
  end if;

  update public.coder_bag b set quantity = b.quantity - 1
   where b.user_id = caller and b.item_id = 'moomoo-milk' and b.quantity > 0;
  if not found then
    return jsonb_build_object('outcome', 'no_milk');
  end if;

  select least(g.milk_hours, left_hours) into taken from public.coder_settings g;
  update public.coder_workplaces w set milk_hours = w.milk_hours + taken where w.id = place.id;
  return jsonb_build_object('outcome', 'drunk', 'hours_left', left_hours - taken);
end;
$$;


-- ============================================================
-- give_ball — hands a request's client a ball from the bag. The ball is
-- spent either way; the client may give an egg in it.
--
--   → {"outcome": "egg", "companion_id": "…", "species": {"ko_name": "고오스", …}}
--   → {"outcome": "hesitated"}
--   → {"outcome": "not_found"} | {"outcome": "not_arrived"} | {"outcome": "already_gave"}
--     | {"outcome": "not_a_ball"} | {"outcome": "no_ball"}
-- ============================================================
create function public.give_ball(workplace_id uuid, item_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  place public.coder_workplaces;
  egg uuid;
begin
  perform public.lock_trainer(caller);
  select * into place from public.coder_workplaces w
   where w.id = give_ball.workplace_id and w.user_id = caller for update;
  if place.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if not public.request_arrived(caller, place.emptied_at) then
    return jsonb_build_object('outcome', 'not_arrived');
  end if;
  if place.gave_egg then
    return jsonb_build_object('outcome', 'already_gave');
  end if;
  if not exists (select 1 from public.coder_balls l where l.item_id = give_ball.item_id) then
    return jsonb_build_object('outcome', 'not_a_ball');
  end if;

  update public.coder_bag b set quantity = b.quantity - 1
   where b.user_id = caller and b.item_id = give_ball.item_id and b.quantity > 0;
  if not found then
    return jsonb_build_object('outcome', 'no_ball');
  end if;

  if not public.client_gives_egg(place.client_id, give_ball.item_id) then
    return jsonb_build_object('outcome', 'hesitated');
  end if;

  egg := public.client_egg(caller, place.client_id, place.is_shiny, give_ball.item_id);
  update public.coder_workplaces w set gave_egg = true where w.id = place.id;
  return jsonb_build_object(
    'outcome', 'egg',
    'companion_id', egg,
    'species', (select jsonb_build_object('species_id', s.id, 'ko_name', s.ko_name, 'en_name', s.en_name)
                  from public.coder_companions c
                  join public.pokedex_species s on s.id = c.species_id
                 where c.id = egg));
end;
$$;


-- ============================================================
-- work — as before, with what milk has taken off each request and whether
-- its client has given an egg, and the milk and balls in the bag. A worker's
-- hours are those it has worked; with the milk they make the shift:
--
--   "rules": {..., "milk_hours": 2}
--   "tools": {"milk": {"id": "moomoo-milk", ..., "quantity": 3},
--             "balls": [{"id": "poke-ball", ..., "quantity": 12}, ...]}
--   "workplaces": [{..., "milk_hours": 2, "gave_egg": false, ...}]
-- ============================================================
create or replace function public.work()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  trainer public.coder_trainers;
  g public.coder_settings;
  hours integer;
  unpaid integer;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  select * into trainer from public.coder_trainers t where t.user_id = caller;
  if not found then
    return jsonb_build_object('started', false);
  end if;
  select * into g from public.coder_settings;

  hours := public.active_hours(caller, trainer.work_started_at);
  unpaid := greatest(0, hours - trainer.work_hours_paid);

  return jsonb_build_object(
    'started', true,
    'points', public.point_balance(caller),
    'rules', jsonb_build_object(
      'points_per_hour', g.points_per_hour,
      'shift_hours', g.shift_hours,
      'min_work_level', g.min_work_level,
      'bonus_every_hours', g.bonus_every_hours,
      'bonus_points', g.bonus_points,
      'milk_hours', g.milk_hours),
    'tools', jsonb_build_object(
      'milk', (select jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                         'sprite', i.sprite,
                                         'quantity', coalesce(b.quantity, 0))
                 from public.pokedex_items i
                 left join public.coder_bag b on b.user_id = caller and b.item_id = i.id
                where i.id = 'moomoo-milk'),
      'balls', (select jsonb_agg(jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                                    'sprite', i.sprite,
                                                    'quantity', coalesce(b.quantity, 0))
                                 order by l.catch_rate, i.id)
                  from public.coder_balls l
                  join public.pokedex_items i on i.id = l.item_id
                  left join public.coder_bag b on b.user_id = caller and b.item_id = i.id)),
    'trainer', jsonb_build_object(
      'name', (select p.display_name from public.profiles p where p.id = caller),
      'hours', hours,
      'hours_paid', trainer.work_hours_paid,
      'points_waiting', unpaid * g.points_per_hour
        + (hours / g.bonus_every_hours - trainer.work_hours_paid / g.bonus_every_hours) * g.bonus_points,
      'hours_to_bonus', g.bonus_every_hours - hours % g.bonus_every_hours),
    'workplaces', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', w.id,
               'slot', w.slot,
               'arrived', up.arrived,
               'hours_to_arrive', case when up.arrived then 0 else g.shift_hours - waited.hours end,
               'client', case when up.arrived then
                   jsonb_build_object('species_id', k.id, 'ko_name', k.ko_name, 'en_name', k.en_name,
                                      'sprites', k.sprites) end,
               'is_shiny', case when up.arrived then w.is_shiny end,
               'shift_hours', case when up.arrived then len.hours end,
               'milk_hours', case when up.arrived then w.milk_hours end,
               'gave_egg', case when up.arrived then w.gave_egg end,
               'task', case when up.arrived then
                   (select jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                      from public.coder_request_tasks t where t.id = w.task_id) end,
               'types', case when up.arrived then
                   (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                     order by t.id = k.type2)
                      from public.pokedex_types t where t.id in (k.type1, k.type2)) end,
               'can_reroll', up.arrived and w.companion_id is null,
               'worker', case when w.companion_id is not null then jsonb_build_object(
                   'companion_id', w.companion_id,
                   'hours', least(shift.hours, len.hours - w.milk_hours),
                   'aptitude', public.aptitude(c.species_id, k.type1, k.type2),
                   'points', public.shift_pay(c.species_id, c.level, k.type1, k.type2),
                   'can_settle', shift.hours + w.milk_hours >= len.hours) end)
             order by w.slot)
        from public.coder_workplaces w
        join public.pokedex_species k on k.id = w.client_id
        left join public.coder_companions c on c.id = w.companion_id
        cross join lateral (select public.active_hours(caller, w.emptied_at) as hours) waited
        cross join lateral (select public.request_arrived(caller, w.emptied_at) as arrived) up
        cross join lateral (select public.active_hours(caller, w.assigned_at) as hours) shift
        cross join lateral (select public.shift_length(w.is_shiny) as hours) len
       where w.user_id = caller), '[]'::jsonb),
    'pokemon', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'species_id', p.id,
               'ko_name', p.ko_name,
               'en_name', p.en_name,
               'sprites', p.sprites,
               'is_shiny', c.is_shiny,
               'gender', c.gender,
               'level', c.level,
               'is_main', c.id = trainer.main_companion_id,
               'types', (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                          order by t.id = p.type2)
                           from public.pokedex_types t where t.id in (p.type1, p.type2)),
               'workplace_id', (select w.id from public.coder_workplaces w where w.companion_id = c.id),
               'ribbons', (select coalesce(jsonb_agg(cr.ribbon_id order by cr.ribbon_id), '[]'::jsonb)
                             from public.coder_companion_ribbons cr where cr.companion_id = c.id),
               'offers', (select jsonb_agg(jsonb_build_object(
                                   'workplace_id', w.id,
                                   'aptitude', public.aptitude(p.id, k.type1, k.type2),
                                   'points', public.shift_pay(p.id, c.level, k.type1, k.type2))
                                 order by w.slot)
                            from public.coder_workplaces w
                            join public.pokedex_species k on k.id = w.client_id
                           where w.user_id = caller and public.request_arrived(caller, w.emptied_at)))
             order by c.level desc, c.hatched_at)
        from public.coder_companions c
        join public.pokedex_species p on p.id = c.species_id
       where c.user_id = caller and c.hatched_at is not null and c.level >= g.min_work_level), '[]'::jsonb));
end;
$$;


-- ============================================================
-- box — as before, with the ball each Pokémon is in.
-- ============================================================
create or replace function public.box(time_zone text default 'UTC')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  hour smallint := public.local_hour(box.time_zone);
  main uuid;
  balance bigint;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  balance := (select coalesce(sum(r.tokens), 0) from public.usage_rollups r where r.user_id = caller)
           - (select coalesce(sum(c.invested_tokens), 0) from public.coder_companions c where c.user_id = caller);

  select t.main_companion_id into main from public.coder_trainers t where t.user_id = caller;
  if not found then
    return jsonb_build_object('started', false, 'balance', balance::text);
  end if;

  return jsonb_build_object(
    'started', true,
    'main_companion_id', main,
    'balance', balance::text,
    'points', public.point_balance(caller),
    'bag', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                          'sprite', i.sprite, 'quantity', b.quantity)
                       order by s.position, i.id)
        from public.coder_bag b
        join public.pokedex_items i on i.id = b.item_id
        left join public.coder_shop_items s on s.item_id = b.item_id
       where b.user_id = caller and b.quantity > 0), '[]'::jsonb),
    'eggs', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'created_at', c.created_at,
               'tokens', c.egg_tokens,
               'tokens_needed', p.hatch_counter::bigint * g.tokens_per_cycle,
               'is_main', c.id = main,
               'markings', c.markings)
             order by c.created_at)
        from public.coder_companions c
        join public.pokedex_species p on p.id = c.species_id
        cross join public.coder_settings g
       where c.user_id = caller and c.hatched_at is null), '[]'::jsonb),
    'pokemon', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'species_id', p.id,
               'form_slug', case when p.form_of is not null then p.slug end,
               'dex_no', dex.number,
               'ko_name', p.ko_name,
               'en_name', p.en_name,
               'sprites', p.sprites,
               'growth_rate', p.growth_rate,
               'types', (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                          order by t.id = p.type2)
                           from public.pokedex_types t where t.id in (p.type1, p.type2)),
               'is_shiny', c.is_shiny,
               'gender', c.gender,
               'ball', (select jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                                  'sprite', i.sprite)
                          from public.pokedex_items i where i.id = c.ball),
               'level', c.level,
               'tokens', c.exp,
               'level_tokens', here.tokens,
               'next_level_tokens', above.tokens,
               'max_tokens', top.tokens,
               'evolves_to', case when nxt.id is not null then
                   jsonb_build_object('species_id', case when not nxt.drawn then nxt.id end,
                                      'ko_name', case when not nxt.drawn then target.ko_name end,
                                      'en_name', case when not nxt.drawn then target.en_name end,
                                      'level', nxt.min_level,
                                      'upside_down', nxt.upside_down,
                                      'spin', nxt.spin) end,
               'can_evolve', coalesce(nxt.ready and not nxt.upside_down and not nxt.spin, false),
               'item_evolutions', coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'species_id', e.id, 'ko_name', s.ko_name, 'en_name', s.en_name,
                            'item', jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                                       'sprite', i.sprite))
                          order by e.id)
                     from public.item_ways(c, hour) e
                     join public.pokedex_species s on s.id = e.id
                     join public.pokedex_items i on i.id = e.item), '[]'::jsonb),
               'workplace_id', (select w.id from public.coder_workplaces w where w.companion_id = c.id),
               'can_receive_egg', c.level >= 50 and c.egg_received_at is null,
               'ribbons', coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'ko_name', r.ko_name, 'en_name', r.en_name,
                                                       'received_at', cr.received_at)
                                    order by cr.received_at)
                     from public.coder_companion_ribbons cr
                     join public.coder_ribbons r on r.id = cr.ribbon_id
                    where cr.companion_id = c.id), '[]'::jsonb),
               'ribbons_waiting', coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'ko_name', r.ko_name, 'en_name', r.en_name) order by r.id)
                     from public.coder_ribbons r
                    where r.id = any (public.eligible_ribbons(c))), '[]'::jsonb),
               'created_at', c.created_at,
               'hatched_at', c.hatched_at,
               'is_main', c.id = main,
               'markings', c.markings)
             order by c.hatched_at)
        from public.coder_companions c
        join public.pokedex_species p on p.id = c.species_id
        cross join public.coder_settings g
        join public.coder_experience_levels here on here.growth_rate = p.growth_rate and here.level = c.level
        join public.coder_experience_levels top on top.growth_rate = p.growth_rate and top.level = 100
        left join public.coder_experience_levels above
          on above.growth_rate = p.growth_rate and above.level = c.level + 1
        left join lateral (select * from public.level_up_ways(c, hour) w order by w.priority limit 1) nxt on true
        left join public.pokedex_species target on target.id = nxt.id
        left join public.pokedex_entries dex on dex.dex = 'national' and dex.species_id = p.id
       where c.user_id = caller and c.hatched_at is not null), '[]'::jsonb));
end;
$$;


-- ============================================================
-- companion_history — as before, with the client who gave the egg, for one
-- from a client's egg.
-- ============================================================
create or replace function public.companion_history(companion_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  found_one public.coder_companions;
begin
  select c.* into found_one
    from public.coder_companions c
   where c.id = companion_history.companion_id and c.user_id = caller;
  if found_one.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  return jsonb_build_object(
    'outcome', 'found',
    'egg_kind', (select jsonb_build_object('id', k.id, 'ko_name', k.ko_name, 'en_name', k.en_name)
                   from public.coder_egg_kinds k where k.id = found_one.egg_kind),
    'egg_from', (select jsonb_build_object('species_id', s.id, 'ko_name', s.ko_name, 'en_name', s.en_name)
                   from public.pokedex_species s where s.id = found_one.egg_from),
    'created_at', found_one.created_at,
    'hatched_at', found_one.hatched_at,
    'main_periods', coalesce((
      select jsonb_agg(jsonb_build_object('started_at', p.started_at, 'ended_at', p.ended_at)
                       order by p.started_at, p.id)
        from public.coder_main_periods p
       where p.companion_id = found_one.id and p.user_id = caller), '[]'::jsonb));
end;
$$;


-- ============================================================
-- Who may call what. See the note in the account migration.
-- ============================================================
revoke all on public.coder_balls from anon, authenticated;
alter table public.coder_balls enable row level security;

revoke execute on function public.use_milk(uuid), public.give_ball(uuid, text) from public;
grant execute on function public.use_milk(uuid), public.give_ball(uuid, text) to authenticated;
