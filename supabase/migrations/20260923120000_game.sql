-- The game: tokens a person's agents spend become experience for a Pokémon.
--
-- Nothing here happens on its own. The web opens the game and asks for the
-- tokens to be invested; hatching, evolving and taking the Lv.50 egg are each
-- a button the person presses, the way Legends: Arceus waits for you to say
-- yes to an evolution. A sync from a machine only records usage and knows
-- nothing about any of this.
--
-- Every change goes through a function below, because each is something a
-- person cannot be trusted to do alone: spend tokens, roll an egg, or change
-- what a Pokémon is. The reference data is readable by anyone signed in; a
-- person's own companions are read through box(), which hides what an egg
-- holds until it hatches.
--
-- The reference rows themselves are in the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes from PokéAPI.


-- ============================================================
-- Reference data.
-- ============================================================
create table public.pokemon_types (
  id   text primary key,
  name text not null
);

-- PokéAPI's names. "medium" is what the games call Medium Fast.
create table public.growth_rates (
  id text primary key
);

-- The games' own tables rather than the formulas behind them: Medium Slow's
-- formula goes negative at level 1, and the table is what the games use.
create table public.experience_levels (
  growth_rate text not null references public.growth_rates,
  level       smallint not null check (level between 1 and 100),
  exp         integer not null check (exp >= 0),
  primary key (growth_rate, level)
);

-- A species knows its one pre-evolution, which is all a Pokémon ever has, and
-- the level it evolves from it at. line_id is the first form of its line and
-- what an egg is rolled as.
create table public.species (
  id              smallint primary key check (id > 0),
  slug            text not null unique,
  name            text not null,
  type1           text not null references public.pokemon_types,
  type2           text references public.pokemon_types,
  growth_rate     text not null references public.growth_rates,
  capture_rate    smallint not null check (capture_rate between 1 and 255),
  hatch_counter   smallint not null check (hatch_counter > 0),
  line_id         smallint not null references public.species,
  evolves_from    smallint references public.species,
  evolution_level smallint check (evolution_level between 2 and 100),

  constraint evolution_is_whole check ((evolves_from is null) = (evolution_level is null)),
  constraint a_line_starts_with_itself check ((evolves_from is null) = (line_id = id))
);

-- Ribbons are kinds, the way the games have many; what earns each is decided
-- in eligible_ribbons().
create table public.ribbons (
  id          text primary key,
  name        text not null,
  description text not null
);

insert into public.ribbons (id, name, description) values
  ('level-100', '레벨 100 리본', 'Lv.100 까지 함께 성장한 포켓몬에게 주는 리본');

-- The balance of the game, in one row. Changing a value changes what happens
-- from then on and nothing already earned: experience is stored, not derived.
create table public.game_settings (
  id                  boolean primary key default true check (id),
  -- K: tokens that make one point of experience.
  tokens_per_exp      integer not null check (tokens_per_exp > 0),
  -- S: tokens that make one step towards hatching.
  tokens_per_step     integer not null check (tokens_per_step > 0),
  -- Steps in one egg cycle; an egg needs its species' hatch_counter of them.
  steps_per_cycle     integer not null check (steps_per_cycle > 0),
  -- The most one claim() may invest, so a backlog arrives over several
  -- claims rather than turning an egg into a Lv.50 in one press.
  claim_limit_tokens  bigint not null check (claim_limit_tokens > 0),
  -- How much likelier a line the person has never had is to hatch.
  unowned_line_weight integer not null check (unowned_line_weight >= 1),
  -- An egg is shiny one time in this many.
  shiny_odds          integer not null check (shiny_odds >= 1)
);

insert into public.game_settings values (true, 2000, 1000, 257, 25000000, 3, 64);


-- ============================================================
-- companions: an egg or a Pokémon, one row for its whole life. Hatching fills
-- hatched_at and level on the same row, and evolving changes species_id.
--
-- invested_tokens is the ledger. What a person may still invest is every
-- token their machines have reported, less the sum of this column over their
-- companions, so it only ever grows and a row is never deleted except with its
-- account. A way to let a Pokémon go will have to keep what it was given.
--
-- markings are the games' six box marks, ● ▲ ■ ♥ ★ ◆ from the lowest bits up,
-- two bits each: 0 off, 1 blue, 2 red. The check refuses a mark set to 3.
-- ============================================================
create table public.companions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users on delete cascade,
  species_id      smallint not null references public.species,
  is_shiny        boolean not null,
  steps           integer not null default 0 check (steps >= 0),
  exp             integer not null default 0 check (exp >= 0),
  level           smallint check (level between 1 and 100),
  invested_tokens public.token_count not null default 0,
  markings        smallint not null default 0
                    constraint markings_are_six_marks
                    check (markings between 0 and 4095 and (markings & (markings >> 1) & 1365) = 0),
  created_at      timestamptz not null default now(),
  hatched_at      timestamptz,
  egg_received_at timestamptz,

  unique (id, user_id),
  constraint a_pokemon_has_a_level check ((hatched_at is null) = (level is null)),
  constraint an_egg_has_no_exp check (hatched_at is not null or exp = 0),
  constraint only_a_pokemon_gives_an_egg check (egg_received_at is null or hatched_at is not null)
);

create index on public.companions (user_id);

create table public.companion_ribbons (
  companion_id uuid not null references public.companions on delete cascade,
  ribbon_id    text not null references public.ribbons,
  received_at  timestamptz not null default now(),
  primary key (companion_id, ribbon_id)
);


-- ============================================================
-- trainers: one row per person playing, made when they start.
--
-- It says which companion is the main one, the one claim() feeds, and naming
-- the owner beside it stops that being anyone else's. It is also the row
-- every change locks first: two tabs claiming at once would otherwise both
-- see the same balance and spend it twice.
-- ============================================================
create table public.trainers (
  user_id           uuid primary key references auth.users on delete cascade,
  main_companion_id uuid not null,
  created_at        timestamptz not null default now(),
  foreign key (main_companion_id, user_id) references public.companions (id, user_id)
);


-- ============================================================
-- Access. As elsewhere: everything away first, then only what the web needs.
-- A person's own rows are not granted at all; box() is how they are read,
-- because an egg's species must not reach the browser before it hatches.
-- ============================================================
revoke all on
  public.pokemon_types, public.growth_rates, public.experience_levels, public.species,
  public.ribbons, public.game_settings, public.companions, public.companion_ribbons,
  public.trainers
  from anon, authenticated;

alter table public.pokemon_types     enable row level security;
alter table public.growth_rates      enable row level security;
alter table public.experience_levels enable row level security;
alter table public.species           enable row level security;
alter table public.ribbons           enable row level security;
alter table public.game_settings     enable row level security;
alter table public.companions        enable row level security;
alter table public.companion_ribbons enable row level security;
alter table public.trainers          enable row level security;

grant select on
  public.pokemon_types, public.growth_rates, public.experience_levels, public.species,
  public.ribbons, public.game_settings
  to authenticated;

create policy "anyone signed in can read types" on public.pokemon_types
  for select to authenticated using (true);
create policy "anyone signed in can read growth rates" on public.growth_rates
  for select to authenticated using (true);
create policy "anyone signed in can read experience levels" on public.experience_levels
  for select to authenticated using (true);
create policy "anyone signed in can read species" on public.species
  for select to authenticated using (true);
create policy "anyone signed in can read ribbons" on public.ribbons
  for select to authenticated using (true);
create policy "anyone signed in can read the game's settings" on public.game_settings
  for select to authenticated using (true);


-- ============================================================
-- roll_egg — a new egg for a person, drawn here and nowhere else.
--
-- The first form of every line is a candidate, weighted by its capture rate
-- the way the games make Pidgey common and Dratini rare. A line the person
-- has never had, not even as an unhatched egg, weighs unowned_line_weight
-- times more, so a collection does not stall on duplicates for years.
--
-- Not granted to anyone: start_game and receive_egg call it as its owner.
-- ============================================================
create function public.roll_egg(owner uuid)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  settings public.game_settings;
  drawn smallint;
  egg uuid;
begin
  select * into settings from public.game_settings;

  with owned as (
    select distinct s.line_id
      from public.companions c
      join public.species s on s.id = c.species_id
     where c.user_id = owner
  ),
  weighted as (
    select s.id,
           s.capture_rate * case when o.line_id is null then settings.unowned_line_weight else 1 end as weight
      from public.species s
      left join owned o on o.line_id = s.id
     where s.evolves_from is null
  ),
  running as (
    select id, sum(weight) over (order by id) as upto, sum(weight) over () as total
      from weighted
  ),
  pick as (
    select random() * max(total) as point from running
  )
  select r.id into drawn
    from running r, pick
   where r.upto > pick.point
   order by r.id
   limit 1;

  insert into public.companions (user_id, species_id, is_shiny)
  values (owner, drawn, floor(random() * settings.shiny_odds) = 0)
  returning id into egg;
  return egg;
end;
$$;


-- ============================================================
-- start_game — the first egg, which is also the first main.
--
--   → {"outcome": "started", "companion_id": "..."}
--   → {"outcome": "already_started"}
--
-- Every token the person's machines have reported is theirs to invest from
-- the start: the machines already count nothing from before they were let in.
-- ============================================================
create function public.start_game()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  egg uuid;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if exists (select 1 from public.trainers t where t.user_id = caller) then
    return jsonb_build_object('outcome', 'already_started');
  end if;

  begin
    egg := public.roll_egg(caller);
    insert into public.trainers (user_id, main_companion_id) values (caller, egg);
  exception when unique_violation then
    -- Another tab started at the same moment. Its egg stands, and this one
    -- goes back with the rest of the block.
    return jsonb_build_object('outcome', 'already_started');
  end;

  return jsonb_build_object('outcome', 'started', 'companion_id', egg);
end;
$$;


-- ============================================================
-- claim — invest what the person has not yet spent into the main companion.
--
--   → {"outcome": "claimed", "tokens": 24998000, "steps": 0, "exp": 12499,
--      "level_before": 7, "level_after": 21, "balance": "123"}
--   → {"outcome": "nothing", "balance": "123"}   nothing left, or nothing fits
--   → {"outcome": "not_main"}
--   → {"outcome": "not_started"}
--
-- It only invests: an egg fills with steps up to what it needs, a Pokémon
-- with experience up to Lv.100, and nothing else changes. What is left over,
-- including the tokens short of one step or one point, stays in the balance.
--
-- The companion is named even though only the main one may take tokens today,
-- so the screen can say which one it means: a main changed in another tab is
-- refused rather than fed by surprise, and sharing out to others later is a
-- change to this check alone.
--
-- The balance is a string for the reason usage() gives its total as one.
-- ============================================================
create function public.claim(companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  settings public.game_settings;
  main uuid;
  target record;
  earned bigint;
  invested bigint;
  budget bigint;
  room bigint;
  added_steps integer := 0;
  added_exp integer := 0;
  spent bigint;
  new_level smallint;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  select t.main_companion_id into main
    from public.trainers t
   where t.user_id = caller
     for update;
  if not found then
    return jsonb_build_object('outcome', 'not_started');
  end if;
  if main <> claim.companion_id then
    return jsonb_build_object('outcome', 'not_main');
  end if;

  select * into settings from public.game_settings;

  select coalesce(sum(r.tokens), 0) into earned
    from public.usage_rollups r
   where r.user_id = caller;
  select coalesce(sum(c.invested_tokens), 0) into invested
    from public.companions c
   where c.user_id = caller;
  budget := least(earned - invested, settings.claim_limit_tokens);

  select c.id, c.steps, c.exp, c.level, c.hatched_at, s.hatch_counter, s.growth_rate
    into target
    from public.companions c
    join public.species s on s.id = c.species_id
   where c.id = main;

  if budget > 0 and target.hatched_at is null then
    room := target.hatch_counter * settings.steps_per_cycle - target.steps;
    added_steps := greatest(0, least(room, budget / settings.tokens_per_step));
  elsif budget > 0 then
    select e.exp - target.exp into room
      from public.experience_levels e
     where e.growth_rate = target.growth_rate and e.level = 100;
    added_exp := greatest(0, least(room, budget / settings.tokens_per_exp));
  end if;

  spent := added_steps::bigint * settings.tokens_per_step + added_exp::bigint * settings.tokens_per_exp;
  if spent = 0 then
    return jsonb_build_object('outcome', 'nothing', 'balance', (earned - invested)::text);
  end if;

  if added_exp > 0 then
    select max(e.level) into new_level
      from public.experience_levels e
     where e.growth_rate = target.growth_rate and e.exp <= target.exp + added_exp;
  end if;

  update public.companions c
     set steps = c.steps + added_steps,
         exp = c.exp + added_exp,
         level = coalesce(new_level, c.level),
         invested_tokens = c.invested_tokens + spent
   where c.id = main;

  return jsonb_build_object(
    'outcome', 'claimed',
    'tokens', spent,
    'steps', added_steps,
    'exp', added_exp,
    'level_before', target.level,
    'level_after', coalesce(new_level, target.level),
    'balance', (earned - invested - spent)::text);
end;
$$;


-- ============================================================
-- A companion of the caller's, locked along with their trainer row. Every
-- button below starts here, so each takes its turn with claim().
--
-- Not granted to anyone.
-- ============================================================
create function public.lock_companion(owner uuid, companion_id uuid)
returns public.companions
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  found public.companions;
begin
  if owner is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  perform 1 from public.trainers t where t.user_id = owner for update;
  select * into found
    from public.companions c
   where c.id = lock_companion.companion_id and c.user_id = owner
     for update;
  return found;
end;
$$;


-- ============================================================
-- hatch — an egg with all its steps becomes a Lv.1 Pokémon.
--
--   → {"outcome": "hatched", "species_id": 4, "is_shiny": false}
--   → {"outcome": "not_ready"} | {"outcome": "not_an_egg"} | {"outcome": "not_found"}
-- ============================================================
create function public.hatch(companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  egg public.companions := public.lock_companion(auth.uid(), hatch.companion_id);
  needed integer;
begin
  if egg.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if egg.hatched_at is not null then
    return jsonb_build_object('outcome', 'not_an_egg');
  end if;

  select s.hatch_counter * g.steps_per_cycle into needed
    from public.species s, public.game_settings g
   where s.id = egg.species_id;
  if egg.steps < needed then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  update public.companions c set hatched_at = now(), level = 1 where c.id = egg.id;
  return jsonb_build_object('outcome', 'hatched', 'species_id', egg.species_id, 'is_shiny', egg.is_shiny);
end;
$$;


-- ============================================================
-- evolve — a Pokémon at or past its evolution level becomes the next form.
--
--   → {"outcome": "evolved", "from": 4, "to": 5}
--   → {"outcome": "not_ready"} | {"outcome": "not_found"}
--
-- Waiting costs nothing: it keeps levelling, and can evolve whenever the
-- person says. Every line here has one next form, so none is chosen.
-- ============================================================
create function public.evolve(companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  pokemon public.companions := public.lock_companion(auth.uid(), evolve.companion_id);
  next_form smallint;
begin
  if pokemon.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  select s.id into next_form
    from public.species s
   where s.evolves_from = pokemon.species_id and s.evolution_level <= pokemon.level
   order by s.id
   limit 1;
  if next_form is null then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  update public.companions c set species_id = next_form where c.id = pokemon.id;
  return jsonb_build_object('outcome', 'evolved', 'from', pokemon.species_id, 'to', next_form);
end;
$$;


-- ============================================================
-- receive_egg — the egg a Pokémon earns by reaching Lv.50, once.
--
--   → {"outcome": "received", "companion_id": "..."}
--   → {"outcome": "not_ready"} | {"outcome": "already_received"} | {"outcome": "not_found"}
-- ============================================================
create function public.receive_egg(companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pokemon public.companions := public.lock_companion(caller, receive_egg.companion_id);
  egg uuid;
begin
  if pokemon.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if pokemon.egg_received_at is not null then
    return jsonb_build_object('outcome', 'already_received');
  end if;
  if coalesce(pokemon.level, 0) < 50 then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  update public.companions c set egg_received_at = now() where c.id = pokemon.id;
  egg := public.roll_egg(caller);
  return jsonb_build_object('outcome', 'received', 'companion_id', egg);
end;
$$;


-- ============================================================
-- receive_ribbon — a ribbon a Pokémon has earned, once each.
--
--   → {"outcome": "received"}
--   → {"outcome": "not_ready"} | {"outcome": "already_received"}
--   → {"outcome": "not_found"} | {"outcome": "unknown_ribbon"}
--
-- What earns a ribbon is written here, beside eligible_ribbons(), which box()
-- uses to say which ones are waiting. The two must agree.
-- ============================================================
create function public.eligible_ribbons(pokemon public.companions)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(r.id order by r.id), '{}')
    from public.ribbons r
   where case r.id
           when 'level-100' then pokemon.level = 100
           else false
         end
     and not exists (
           select 1 from public.companion_ribbons cr
            where cr.companion_id = pokemon.id and cr.ribbon_id = r.id);
$$;

create function public.receive_ribbon(companion_id uuid, ribbon_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  pokemon public.companions := public.lock_companion(auth.uid(), receive_ribbon.companion_id);
begin
  if pokemon.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if not exists (select 1 from public.ribbons r where r.id = receive_ribbon.ribbon_id) then
    return jsonb_build_object('outcome', 'unknown_ribbon');
  end if;
  if exists (select 1 from public.companion_ribbons cr
              where cr.companion_id = pokemon.id and cr.ribbon_id = receive_ribbon.ribbon_id) then
    return jsonb_build_object('outcome', 'already_received');
  end if;
  if not receive_ribbon.ribbon_id = any (public.eligible_ribbons(pokemon)) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  insert into public.companion_ribbons (companion_id, ribbon_id)
  values (pokemon.id, receive_ribbon.ribbon_id);
  return jsonb_build_object('outcome', 'received');
end;
$$;


-- ============================================================
-- set_main and set_markings — the two things a person changes directly.
--
--   → {"outcome": "set"} | {"outcome": "not_found"}
--
-- Changing the main settles nothing: the balance belongs to no companion
-- until it is claimed, so the next claim() simply feeds the new one.
-- ============================================================
create function public.set_main(companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  chosen public.companions := public.lock_companion(caller, set_main.companion_id);
begin
  if chosen.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  update public.trainers t set main_companion_id = chosen.id where t.user_id = caller;
  return jsonb_build_object('outcome', 'set');
end;
$$;

create function public.set_markings(companion_id uuid, markings smallint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  chosen public.companions := public.lock_companion(auth.uid(), set_markings.companion_id);
begin
  if chosen.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  -- The table's check refuses a mark set to 3, with 23514.
  update public.companions c set markings = set_markings.markings where c.id = chosen.id;
  return jsonb_build_object('outcome', 'set');
end;
$$;


-- ============================================================
-- box — everything the person has, for the screen.
--
--   → {"started": true, "main_companion_id": "...", "balance": "123",
--      "eggs":    [{"id", "created_at", "steps", "steps_needed", "is_main", "markings"}],
--      "pokemon": [{"id", "species_id", "name", "types": [{"id", "name"}],
--                   "is_shiny", "level", "exp", "level_exp", "next_level_exp",
--                   "evolves_to": {"id", "name", "level"} | null, "can_evolve",
--                   "can_receive_egg", "ribbons": [{"id", "name", "received_at"}],
--                   "ribbons_waiting": [{"id", "name"}], "created_at", "hatched_at",
--                   "is_main", "markings"}]}
--   → {"started": false, "balance": "123"}
--
-- An egg says how many steps it needs, which hints at what it holds, as the
-- games do when they say an egg will take a while. It says nothing more.
-- ============================================================
create function public.box()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  main uuid;
  balance bigint;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  balance := (select coalesce(sum(r.tokens), 0) from public.usage_rollups r where r.user_id = caller)
           - (select coalesce(sum(c.invested_tokens), 0) from public.companions c where c.user_id = caller);

  select t.main_companion_id into main from public.trainers t where t.user_id = caller;
  if not found then
    return jsonb_build_object('started', false, 'balance', balance::text);
  end if;

  return jsonb_build_object(
    'started', true,
    'main_companion_id', main,
    'balance', balance::text,
    'eggs', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'created_at', c.created_at,
               'steps', c.steps,
               'steps_needed', s.hatch_counter * g.steps_per_cycle,
               'is_main', c.id = main,
               'markings', c.markings)
             order by c.created_at)
        from public.companions c
        join public.species s on s.id = c.species_id
        cross join public.game_settings g
       where c.user_id = caller and c.hatched_at is null), '[]'::jsonb),
    'pokemon', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'species_id', s.id,
               'name', s.name,
               'types', (select jsonb_agg(jsonb_build_object('id', pt.id, 'name', pt.name)
                                          order by pt.id = s.type2)
                           from public.pokemon_types pt where pt.id in (s.type1, s.type2)),
               'is_shiny', c.is_shiny,
               'level', c.level,
               'exp', c.exp,
               'level_exp', here.exp,
               'next_level_exp', above.exp,
               'evolves_to', case when nxt.id is not null then
                   jsonb_build_object('id', nxt.id, 'name', nxt.name, 'level', nxt.evolution_level) end,
               'can_evolve', coalesce(c.level >= nxt.evolution_level, false),
               'can_receive_egg', c.level >= 50 and c.egg_received_at is null,
               'ribbons', coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name, 'received_at', cr.received_at)
                                    order by cr.received_at)
                     from public.companion_ribbons cr
                     join public.ribbons r on r.id = cr.ribbon_id
                    where cr.companion_id = c.id), '[]'::jsonb),
               'ribbons_waiting', coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name) order by r.id)
                     from public.ribbons r
                    where r.id = any (public.eligible_ribbons(c))), '[]'::jsonb),
               'created_at', c.created_at,
               'hatched_at', c.hatched_at,
               'is_main', c.id = main,
               'markings', c.markings)
             order by c.hatched_at)
        from public.companions c
        join public.species s on s.id = c.species_id
        join public.experience_levels here on here.growth_rate = s.growth_rate and here.level = c.level
        left join public.experience_levels above on above.growth_rate = s.growth_rate and above.level = c.level + 1
        left join lateral (
          select n.id, n.name, n.evolution_level
            from public.species n
           where n.evolves_from = s.id
           order by n.id
           limit 1) nxt on true
       where c.user_id = caller and c.hatched_at is not null), '[]'::jsonb));
end;
$$;


-- ============================================================
-- Who may call what. See the note in the account migration.
-- ============================================================
revoke execute on function
  public.roll_egg(uuid),
  public.lock_companion(uuid, uuid),
  public.eligible_ribbons(public.companions),
  public.start_game(),
  public.claim(uuid),
  public.hatch(uuid),
  public.evolve(uuid),
  public.receive_egg(uuid),
  public.receive_ribbon(uuid, text),
  public.set_main(uuid),
  public.set_markings(uuid, smallint),
  public.box()
  from public;

grant execute on function
  public.start_game(),
  public.claim(uuid),
  public.hatch(uuid),
  public.evolve(uuid),
  public.receive_egg(uuid),
  public.receive_ribbon(uuid, text),
  public.set_main(uuid),
  public.set_markings(uuid, smallint),
  public.box()
  to authenticated;
