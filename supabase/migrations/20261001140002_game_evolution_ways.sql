-- Every way to evolve the game can offer, not only a level or a stone.
--
-- What the games ask that the game here cannot see, it asks another way:
--
--   - A trade is a Linking Cord, as the games since Legends: Arceus have it,
--     and a trade holding an item is that item, used as a stone is.
--     Karrablast and Shelmet trade for each other: a Linking Cord evolves
--     Shelmet when a Karrablast is in the box, and leaves a Shelmet Shell,
--     which evolves Karrablast.
--   - A held item at a time of day is that item, used then.
--   - A place is a stone: a Thunder Stone for Mt. Coronet's and Poni's
--     magnetic fields, a Leaf Stone for the moss rock, an Ice Stone for the
--     ice rock and Mount Lanakila.
--   - Feebas's beauty is a Prism Scale, Sliggoo's rain a Damp Rock, and
--     Meltan's 400 candies in Pokémon GO one Meltan Candy.
--   - A time of day is the person's own: day from 6:00 to 17:59, night from
--     18:00 to 5:59, and dusk from 17:00 to 17:59.
--   - Friendship and affection are reached on 4 a level and 15 an hour as
--     the partner, against 160: Lv.40 alone, or Lv.25 and four hours.
--   - Knowing a move, or a move of a type, is having done a request of that
--     type: Piloswine, knowing Ancient Power, by a Rock one.
--   - Another Pokémon in the party is one in the box.
--   - Attack against Defense, and Wurmple's personality, are a draw at the
--     time, weighted as an egg is: a form the person has none of, nor
--     anything it became, is unowned_line_weight times as likely.
--   - Cosmoem, which becomes Solgaleo in Sun and Lunala in Moon, becomes
--     Solgaleo by day and Lunala by night.
--   - Inkay's console turned upside down is the screen's: the server cannot
--     see it, and takes it as done.
--   - Nincada leaves a Shedinja as it becomes Ninjask, at Lv.1, since a token
--     is a point of experience and none were spent on it.
--   - Own Tempo Rockruff is any Rockruff here, and reaches Dusk Lycanroc.
--
-- Mega Evolution, Primal Reversion and Ultra Burst are left out.


-- ============================================================
-- The balance of friendship, beside the rest in coder_settings.
-- ============================================================
alter table public.coder_settings
  add column friendship_per_level        smallint not null default 4   check (friendship_per_level >= 0),
  add column friendship_per_partner_hour smallint not null default 15  check (friendship_per_partner_hour >= 0),
  add column friendship_needed           smallint not null default 160 check (friendship_needed > 0);

alter table public.coder_settings
  alter column friendship_per_level drop default,
  alter column friendship_per_partner_hour drop default,
  alter column friendship_needed drop default;


-- ============================================================
-- coder_requests_done: each request a Pokémon has settled, and for whom,
-- whose types are the request's.
--
-- Nobody is granted it.
-- ============================================================
create table public.coder_requests_done (
  id           bigint generated always as identity primary key,
  user_id      uuid not null,
  companion_id uuid not null,
  client_id    integer not null references public.pokedex_species,
  done_at      timestamptz not null default now(),
  foreign key (companion_id, user_id) references public.coder_companions (id, user_id) on delete cascade
);

create index on public.coder_requests_done (companion_id);

revoke all on public.coder_requests_done from anon, authenticated;
alter table public.coder_requests_done enable row level security;


-- ============================================================
-- coder_location_items: the stone a place is.
-- ============================================================
create table public.coder_location_items (
  location text primary key references public.pokedex_locations,
  item_id  text not null references public.pokedex_items
);

insert into public.coder_location_items (location, item_id) values
  ('mt-coronet',       'thunder-stone'),
  ('vast-poni-canyon', 'thunder-stone'),
  ('eterna-forest',    'leaf-stone'),
  ('sinnoh-route-217', 'ice-stone'),
  ('mount-lanakila',   'ice-stone');

revoke all on public.coder_location_items from anon, authenticated;
alter table public.coder_location_items enable row level security;
grant select on public.coder_location_items to authenticated;
create policy "anyone signed in can read which stone a place is" on public.coder_location_items
  for select to authenticated using (true);


-- ============================================================
-- The Shelmet Shell is the game's own, so no pokedex names it: no sprite.
-- ============================================================
insert into public.pokedex_items (id, ko_name, en_name, sprite) values
  ('shelmet-shell', '쪼마리의껍질', 'Shelmet Shell', null);


-- ============================================================
-- Sold as the stones are, after them. The Shelmet Shell is not sold.
-- ============================================================
update public.coder_shop_items set position = position + 20 where egg_kind is not null;
insert into public.coder_shop_items (id, item_id, egg_kind, price, position) values
  ('linking-cord',   'linking-cord',   null, 5000, 11),
  ('kings-rock',     'kings-rock',     null, 5000, 12),
  ('metal-coat',     'metal-coat',     null, 5000, 13),
  ('dragon-scale',   'dragon-scale',   null, 5000, 14),
  ('up-grade',       'up-grade',       null, 5000, 15),
  ('dubious-disc',   'dubious-disc',   null, 5000, 16),
  ('deep-sea-tooth', 'deep-sea-tooth', null, 5000, 17),
  ('deep-sea-scale', 'deep-sea-scale', null, 5000, 18),
  ('protector',      'protector',      null, 5000, 19),
  ('electirizer',    'electirizer',    null, 5000, 20),
  ('magmarizer',     'magmarizer',     null, 5000, 21),
  ('reaper-cloth',   'reaper-cloth',   null, 5000, 22),
  ('sachet',         'sachet',         null, 5000, 23),
  ('whipped-dream',  'whipped-dream',  null, 5000, 24),
  ('oval-stone',     'oval-stone',     null, 5000, 25),
  ('razor-claw',     'razor-claw',     null, 5000, 26),
  ('razor-fang',     'razor-fang',     null, 5000, 27),
  ('prism-scale',    'prism-scale',    null, 5000, 28),
  ('damp-rock',      'damp-rock',      null, 5000, 29),
  ('meltan-candy',   'meltan-candy',   null, 5000, 30);


-- ============================================================
-- Helpers. None is granted to anyone.
-- ============================================================

-- The hour it is where the person is, 0 to 23. A time zone Postgres does not
-- know is taken as UTC, rather than refusing the button.
create function public.local_hour(time_zone text)
returns smallint
language plpgsql
stable
set search_path = ''
as $$
begin
  return extract(hour from now() at time zone coalesce(local_hour.time_zone, 'UTC'));
exception when invalid_parameter_value then
  return extract(hour from now() at time zone 'UTC');
end;
$$;

-- Whether it is that time of day at an hour; no time of day is any.
create function public.at_time_of_day(time_of_day text, hour smallint)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case at_time_of_day.time_of_day
           when 'day'   then hour between 6 and 17
           when 'night' then hour not between 6 and 17
           when 'dusk'  then hour = 17
           else true
         end;
$$;

-- Whether a Pokémon is friendly enough to evolve on friendship or affection.
create function public.friendly(pokemon public.coder_companions)
returns boolean
language sql
stable
set search_path = ''
as $$
  select g.friendship_per_level * coalesce(pokemon.level, 0)
       + g.friendship_per_partner_hour
         * coalesce((select sum(extract(epoch from coalesce(m.ended_at, now()) - m.started_at)) / 3600
                       from public.coder_main_periods m
                      where m.companion_id = pokemon.id), 0)
       >= g.friendship_needed
    from public.coder_settings g;
$$;

-- Whether a Pokémon has done a request of a type.
create function public.did_request(companion_id uuid, type text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.coder_requests_done d
                   join public.pokedex_species k on k.id = d.client_id
                  where d.companion_id = did_request.companion_id
                    and did_request.type in (k.type1, k.type2));
$$;

-- Whether the box holds another Pokémon, hatched, of a species in any form,
-- or of a type.
create function public.in_box(pokemon public.coder_companions, species_id integer, type text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.coder_companions o
                   join public.pokedex_species s on s.id = o.species_id
                  where o.user_id = pokemon.user_id
                    and o.id is distinct from pokemon.id
                    and o.hatched_at is not null
                    and (in_box.species_id is null or coalesce(s.form_of, s.id) = in_box.species_id)
                    and (in_box.type is null or in_box.type in (s.type1, s.type2)));
$$;

-- How many of a person's Pokémon are a form or have evolved from it: whether
-- a draw counts it as a line they have.
create function public.owned_line(owner uuid, species_id integer)
returns integer
language sql
stable
set search_path = ''
as $$
  with recursive up as (
    select o.id as companion_id, s.id, s.form_of, s.evolves_from_id
      from public.coder_companions o
      join public.pokedex_species s on s.id = o.species_id
     where o.user_id = owner and o.hatched_at is not null
    union all
    select up.companion_id, s.id, s.form_of, s.evolves_from_id
      from up join public.pokedex_species s on s.id = up.evolves_from_id
  )
  select count(distinct companion_id)::integer from up
   where coalesce(up.form_of, up.id) = owned_line.species_id or up.id = owned_line.species_id;
$$;


-- ============================================================
-- level_up_ways — what a Pokémon becomes on its own, no item used, and
-- whether it may now. In the order it is tried: a way of its region before
-- the way anywhere else, a way asking more before one asking less, Sylveon
-- before Espeon and Umbreon, Dusk Lycanroc before Midday.
--
-- drawn marks a way that is one of a draw; upside_down, one that asks the
-- screen to turn Inkay over first.
--
-- Not granted to anyone.
-- ============================================================
create function public.level_up_ways(pokemon public.coder_companions, hour smallint)
returns table (id integer, min_level smallint, ready boolean, drawn boolean, upside_down boolean, priority bigint)
language sql
stable
set search_path = ''
as $$
  select w.id, w.min_level, w.ready, w.drawn, w.upside_down,
         row_number() over (order by w.ready desc, w.regional desc, w.affection desc, w.dusk desc, w.id)
    from (
      select p.id, m.level as min_level,
             coalesce(pokemon.level >= m.level, true)
               and (coalesce(m.min_happiness, m.min_affection) is null or public.friendly(pokemon))
               and public.at_time_of_day(m.time_of_day, hour)
               and public.at_time_of_day(case m.version when 'sun' then 'day' when 'moon' then 'night' end, hour)
               and (coalesce(mv.type, m.known_move_type) is null
                    or public.did_request(pokemon.id, coalesce(mv.type, m.known_move_type)))
               and (m.party_species_id is null or public.in_box(pokemon, m.party_species_id, null))
               and (m.party_type is null or public.in_box(pokemon, null, m.party_type)) as ready,
             m.chance is not null or m.relative_physical_stats is not null as drawn,
             m.turn_upside_down as upside_down,
             m.region is not null as regional,
             m.min_affection is not null as affection,
             coalesce(m.time_of_day = 'dusk', false) as dusk
        from public.pokedex_species f
        join public.pokedex_species p
          on p.evolves_from_id = f.id
          or (p.evolves_from_id = f.form_of
              and not exists (select 1 from public.pokedex_species q
                               where coalesce(q.form_of, q.id) = coalesce(p.form_of, p.id)
                                 and q.evolves_from_id = f.id))
          or (f.slug = 'rockruff' and p.slug = 'lycanroc-dusk')
        join public.pokedex_evolution_methods m on m.id = p.evolution_method
        left join public.pokedex_moves mv on mv.id = m.known_move
       where f.id = pokemon.species_id
         and m.trigger = 'level-up' and m.item is null and m.held_item is null
         and m.location is null and m.min_beauty is null and not m.needs_overworld_rain
         and (m.gender is null or m.gender = pokemon.gender)
         and (m.region is null or m.region = pokemon.egg_kind)
         and (m.version is null or m.version in ('sun', 'moon'))
    ) w;
$$;


-- ============================================================
-- item_ways — what a Pokémon becomes with which item, now. An item with more
-- than one way takes its region's, as an Alola egg's Pikachu takes a Thunder
-- Stone to Alolan Raichu.
--
-- Not granted to anyone.
-- ============================================================
create function public.item_ways(pokemon public.coder_companions, hour smallint)
returns table (id integer, item text)
language sql
stable
set search_path = ''
as $$
  select distinct on (w.item) w.id, w.item
    from (
      select p.id, m.region,
             case
               when m.trigger = 'use-item' then m.item
               when m.trigger = 'trade' and f.slug = 'karrablast' then 'shelmet-shell'
               when m.trigger = 'trade' then coalesce(m.held_item, 'linking-cord')
               when m.held_item is not null then m.held_item
               when m.location is not null then l.item_id
               when m.min_beauty is not null then 'prism-scale'
               when m.needs_overworld_rain then 'damp-rock'
               when m.trigger = 'meltan-candies' then 'meltan-candy'
             end as item
        from public.pokedex_species f
        join public.pokedex_species p on p.evolves_from_id = f.id
        join public.pokedex_evolution_methods m on m.id = p.evolution_method
        left join public.coder_location_items l on l.location = m.location
       where f.id = pokemon.species_id
         and (m.trigger in ('use-item', 'trade', 'meltan-candies')
              or (m.trigger = 'level-up'
                  and (m.held_item is not null or m.location is not null
                       or m.min_beauty is not null or m.needs_overworld_rain)))
         and coalesce(pokemon.level >= m.level, true)
         and public.at_time_of_day(m.time_of_day, hour)
         and (m.gender is null or m.gender = pokemon.gender)
         and (m.region is null or m.region = pokemon.egg_kind)
         and m.version is null and m.known_move is null and m.party_species_id is null
         and (m.trade_species_id is null or f.slug = 'karrablast'
              or public.in_box(pokemon, m.trade_species_id, null))
    ) w
   where w.item is not null
   order by w.item, w.region is null, w.id;
$$;


-- ============================================================
-- shed — after Nincada becomes Ninjask, the Shedinja its shell leaves, at
-- Lv.1, of its egg and as shiny as it; or null.
--
-- Hatched in two steps so the dex records it, as a hatch does.
--
-- Not granted to anyone.
-- ============================================================
create function public.shed(pokemon public.coder_companions)
returns uuid
language plpgsql
volatile
set search_path = ''
as $$
declare
  shell integer;
  left_behind uuid;
begin
  select p.id into shell
    from public.pokedex_species p
    join public.pokedex_evolution_methods m on m.id = p.evolution_method
   where p.evolves_from_id = pokemon.species_id and m.trigger = 'shed';
  if shell is null then
    return null;
  end if;

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, gender)
  values (pokemon.user_id, shell, pokemon.egg_kind, pokemon.is_shiny, public.draw_gender(shell))
  returning id into left_behind;
  update public.coder_companions c set hatched_at = now(), level = 1 where c.id = left_behind;
  return left_behind;
end;
$$;


-- ============================================================
-- evolve — the first way it may take now, in the person's time zone. A
-- draw weighs each form it may become as roll_egg() weighs a species: one
-- the person has none of, nor anything it became, is unowned_line_weight
-- times as likely. Nincada leaves a Shedinja behind.
--
--   {"companion_id": "...", "time_zone": "Asia/Seoul"}
--
--   → {"outcome": "evolved", "from": 290, "to": 291, "shed": "..."}
--   → {"outcome": "not_ready"} | {"outcome": "working"} | {"outcome": "not_found"}
-- ============================================================
drop function public.evolve(uuid);
create function public.evolve(companion_id uuid, time_zone text default 'UTC')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  pokemon public.coder_companions := public.lock_companion(auth.uid(), evolve.companion_id);
  hour smallint := public.local_hour(evolve.time_zone);
  way record;
  next_form integer;
  left_behind uuid;
begin
  if pokemon.id is null or pokemon.hatched_at is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if public.at_work(pokemon.id) then
    return jsonb_build_object('outcome', 'working');
  end if;

  select * into way from public.level_up_ways(pokemon, hour) w where w.ready order by w.priority limit 1;
  if not found then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  next_form := way.id;
  if way.drawn then
    with weighted as (
      select w.id,
             case when public.owned_line(pokemon.user_id, w.id) = 0 then g.unowned_line_weight else 1 end as weight
        from public.level_up_ways(pokemon, hour) w
       cross join public.coder_settings g
       where w.ready and w.drawn
    ),
    running as (
      select id, sum(weight) over (order by id) as upto, sum(weight) over () as total
        from weighted
    ),
    pick as (
      select random() * max(total) as point from running
    )
    select r.id into next_form
      from running r, pick
     where r.upto > pick.point
     order by r.id
     limit 1;
  end if;

  update public.coder_companions c set species_id = next_form where c.id = pokemon.id;
  left_behind := public.shed(pokemon);
  return jsonb_strip_nulls(jsonb_build_object(
    'outcome', 'evolved', 'from', pokemon.species_id, 'to', next_form, 'shed', left_behind));
end;
$$;


-- ============================================================
-- use_item — as before, with every item way, in the person's time zone. A
-- Linking Cord used on Shelmet leaves its shell in the bag.
--
--   → {"outcome": "evolved", "from": 616, "to": 617, "received": "shelmet-shell"}
-- ============================================================
drop function public.use_item(uuid, text);
create function public.use_item(companion_id uuid, item_id text, time_zone text default 'UTC')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pokemon public.coder_companions := public.lock_companion(caller, use_item.companion_id);
  next_form integer;
  received text;
begin
  if pokemon.id is null or pokemon.hatched_at is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if public.at_work(pokemon.id) then
    return jsonb_build_object('outcome', 'working');
  end if;
  if not exists (select 1 from public.coder_bag b
                  where b.user_id = caller and b.item_id = use_item.item_id and b.quantity > 0) then
    return jsonb_build_object('outcome', 'not_in_bag');
  end if;

  select e.id into next_form from public.item_ways(pokemon, public.local_hour(use_item.time_zone)) e
   where e.item = use_item.item_id;
  if next_form is null then
    return jsonb_build_object('outcome', 'no_effect');
  end if;

  update public.coder_bag b set quantity = b.quantity - 1
   where b.user_id = caller and b.item_id = use_item.item_id;
  update public.coder_companions c set species_id = next_form where c.id = pokemon.id;

  if use_item.item_id = 'linking-cord'
     and (select s.slug from public.pokedex_species s where s.id = pokemon.species_id) = 'shelmet' then
    received := 'shelmet-shell';
    insert into public.coder_bag (user_id, item_id, quantity) values (caller, received, 1)
    on conflict on constraint coder_bag_pkey do update set quantity = public.coder_bag.quantity + 1;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'outcome', 'evolved', 'from', pokemon.species_id, 'to', next_form, 'received', received));
end;
$$;


-- ============================================================
-- settle — as before, and the request is kept as one the Pokémon did.
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
  if public.active_hours(caller, place.assigned_at) < (select g.shift_hours from public.coder_settings g) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  select * into pokemon from public.coder_companions c where c.id = place.companion_id;
  select public.shift_pay(pokemon.species_id, pokemon.level, k.type1, k.type2) into pay
    from public.pokedex_species k where k.id = place.client_id;
  if pay > 0 then
    insert into public.coder_point_entries (user_id, points, reason) values (caller, pay, 'shift');
  end if;
  insert into public.coder_requests_done (user_id, companion_id, client_id)
  values (caller, pokemon.id, place.client_id);

  client := public.roll_client();
  update public.coder_workplaces w
     set client_id = client, task_id = public.roll_task(client), emptied_at = null,
         companion_id = null, assigned_at = null
   where w.id = place.id;
  return jsonb_build_object('outcome', 'settled', 'points', pay);
end;
$$;


-- ============================================================
-- box — as before, in the person's time zone, with every way.
--
-- evolves_to is the first way it may take now, or else the first it may
-- take later: a draw names no form, and one Inkay takes says it asks the
-- screen to turn it over. can_evolve is false for that one, which the screen
-- offers only upside down.
-- ============================================================
drop function public.box();
create function public.box(time_zone text default 'UTC')
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
                                      'upside_down', nxt.upside_down) end,
               'can_evolve', coalesce(nxt.ready and not nxt.upside_down, false),
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
-- What the ways above take the place of.
-- ============================================================
drop function public.level_up_evolution(integer, text);
drop function public.item_evolutions(integer, text, text);


-- ============================================================
-- Who may call what. See the note in the account migration.
-- ============================================================
revoke execute on function
  public.local_hour(text),
  public.at_time_of_day(text, smallint),
  public.friendly(public.coder_companions),
  public.did_request(uuid, text),
  public.in_box(public.coder_companions, integer, text),
  public.owned_line(uuid, integer),
  public.level_up_ways(public.coder_companions, smallint),
  public.item_ways(public.coder_companions, smallint),
  public.shed(public.coder_companions),
  public.evolve(uuid, text),
  public.use_item(uuid, text, text),
  public.box(text)
  from public;

grant execute on function
  public.evolve(uuid, text),
  public.use_item(uuid, text, text),
  public.box(text)
  to authenticated;
