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
-- what a Pokémon is. A person's own companions are read through box(), which
-- hides what an egg holds until it hatches.
--
-- What a Pokémon is comes from the pokedex_ tables, in the migrations before
-- this one; what the game makes of it is here.


-- ============================================================
-- level_only_methods — the ways to evolve the game can offer: a level-up at a
-- level, with nothing else asked. coder_egg_species keeps its families to these,
-- and level_up_evolution() finds them, so the two agree.
--
-- Not granted to anyone.
-- ============================================================
create function public.level_only_methods()
returns setof text
language sql
stable
set search_path = ''
as $$
  select m.id from public.pokedex_evolution_methods m
   where m.trigger = 'level-up' and m.level is not null and m.item is null;
$$;


-- ============================================================
-- coder_egg_kinds and coder_egg_species: the kinds of egg there are, and what
-- each can hold, how likely.
--
-- A national egg can hold anything the game hatches; a generation's egg only
-- that generation's. With Generation I alone in the pokedex the two hold the
-- same, and every egg handed out today is a national one; the kinds are here
-- so a later egg can be narrower.
--
-- What any egg can hold is the first form of a family whose evolutions, if it
-- has any, are all plain level-ups, so that a button and a level are all any
-- of them ever needs. A family with a stone or a trade anywhere in it is left
-- out whole rather than cut short. One that never evolves is in, legendaries
-- and Ditto included, though the games hatch none of those from an egg.
--
-- How likely each is comes from its rarity, a tier with a weight of its own,
-- so the odds are the game's to set rather than the pokedex's. Which tier a
-- species is in was decided by hand, from how Red and Green hand it over: on
-- the first routes is common, later or in one place is uncommon, a trade, a
-- one-off or a low chance is rare, and the starters, the fossils, Dratini's
-- family and Porygon are very rare. Legendaries and mythicals are mythic.
--
-- At these weights a person has every species but the mythic ones after about
-- 140 eggs, and the mythic ones take as long again.
-- ============================================================
create table public.coder_egg_rarities (
  id      text primary key,
  ko_name text,
  en_name text,
  weight  integer not null check (weight > 0)
);

insert into public.coder_egg_rarities (id, ko_name, en_name, weight) values
  ('common',    '흔함',      'Common',    10),
  ('uncommon',  '보통',      'Uncommon',   8),
  ('rare',      '드묾',      'Rare',       6),
  ('very-rare', '매우 드묾', 'Very rare',  4),
  ('mythic',    '신비',      'Mythic',     1);

-- Every species an egg can hold, by tier. A species missing here, or named
-- here but unable to hatch, fails the insert below rather than going quiet.
create temporary table egg_rarity (slug text primary key, rarity text not null);
insert into egg_rarity (slug, rarity) values
  ('caterpie', 'common'), ('weedle', 'common'), ('pidgey', 'common'), ('rattata', 'common'),
  ('spearow', 'common'), ('ekans', 'common'), ('zubat', 'common'), ('diglett', 'common'),
  ('meowth', 'common'), ('goldeen', 'common'), ('magikarp', 'common'),

  ('sandshrew', 'uncommon'), ('paras', 'uncommon'), ('venonat', 'uncommon'), ('psyduck', 'uncommon'),
  ('mankey', 'uncommon'), ('tentacool', 'uncommon'), ('ponyta', 'uncommon'), ('slowpoke', 'uncommon'),
  ('magnemite', 'uncommon'), ('doduo', 'uncommon'), ('seel', 'uncommon'), ('grimer', 'uncommon'),
  ('onix', 'uncommon'), ('krabby', 'uncommon'), ('voltorb', 'uncommon'), ('cubone', 'uncommon'),
  ('koffing', 'uncommon'), ('rhyhorn', 'uncommon'), ('kangaskhan', 'uncommon'), ('scyther', 'uncommon'),
  ('jynx', 'uncommon'), ('electabuzz', 'uncommon'), ('magmar', 'uncommon'), ('pinsir', 'uncommon'),
  ('tauros', 'uncommon'),

  ('farfetchd', 'rare'), ('drowzee', 'rare'), ('hitmonlee', 'rare'), ('hitmonchan', 'rare'),
  ('lickitung', 'rare'), ('chansey', 'rare'), ('tangela', 'rare'), ('horsea', 'rare'),
  ('mr-mime', 'rare'), ('lapras', 'rare'), ('ditto', 'rare'), ('snorlax', 'rare'),

  ('bulbasaur', 'very-rare'), ('charmander', 'very-rare'), ('squirtle', 'very-rare'),
  ('porygon', 'very-rare'), ('omanyte', 'very-rare'), ('kabuto', 'very-rare'),
  ('aerodactyl', 'very-rare'), ('dratini', 'very-rare'),

  ('articuno', 'mythic'), ('zapdos', 'mythic'), ('moltres', 'mythic'), ('mewtwo', 'mythic'),
  ('mew', 'mythic');

create table public.coder_egg_kinds (
  id      text primary key,
  ko_name text,
  en_name text
);

insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('national', '전국 알', 'National Egg'),
  ('gen1', '1세대 알', 'Generation I Egg');

create table public.coder_egg_species (
  egg_kind   text not null references public.coder_egg_kinds,
  species_id integer not null references public.pokedex_species,
  rarity     text not null references public.coder_egg_rarities,
  primary key (egg_kind, species_id)
);

create temporary table hatchable as
select s.id, s.slug, s.generation
  from public.pokedex_species s
 where s.evolves_from_id is null
   and not exists (
         select 1 from public.pokedex_species d
          where public.pokedex_first_form(d.id) = s.id
            and d.evolves_from_id is not null
            and d.evolution_method not in (select public.level_only_methods()));

do $$
begin
  if exists (select slug from hatchable except select slug from egg_rarity)
     or exists (select slug from egg_rarity except select slug from hatchable) then
    raise exception 'every species an egg can hold needs a rarity, and every rarity such a species';
  end if;
end;
$$;

insert into public.coder_egg_species (egg_kind, species_id, rarity)
select 'national', h.id, r.rarity from hatchable h join egg_rarity r using (slug)
union all
select 'gen1', h.id, r.rarity from hatchable h join egg_rarity r using (slug) where h.generation = 1;

drop table hatchable, egg_rarity;

-- Ribbons are kinds, the way the games have many; what earns each is decided
-- in eligible_ribbons().
create table public.coder_ribbons (
  id             text primary key,
  ko_name        text,
  en_name        text,
  ko_description text,
  en_description text
);

insert into public.coder_ribbons (id, ko_name, en_name, ko_description, en_description) values
  ('level-100', '레벨 100 리본', 'Level 100 Ribbon',
   'Lv.100 까지 함께 성장한 포켓몬에게 주는 리본', 'A ribbon for a Pokémon that grew all the way to Lv.100');

-- ============================================================
-- coder_experience_levels: the tokens a Pokémon needs to reach each level.
--
-- A token is a point of experience, so this is the game's own curve rather
-- than the games' tables times a rate. It keeps their growth rates, and their
-- order, a slow Pokémon needing a quarter more than a medium one at Lv.100 as
-- in the games, but not their shape: the games' curves are cubic, making
-- Lv.100 eight times Lv.50, and this one is flatter, so Lv.50 is 40% of
-- Lv.100.
--
--   tokens(level) = total × ((level − 1) / 99) ^ p,  with p set so that
--   tokens(50) = 0.4 × tokens(100)
--
-- Medium Fast, the rate most Pokémon grow at, reaches Lv.50 on 200M tokens
-- and Lv.100 on 500M: at 200M a day, a day and two and a half days. The other
-- rates keep their distance from it. The rows are the game's to change one by
-- one; this only writes the first of them.
-- ============================================================
create table public.coder_experience_levels (
  growth_rate text not null references public.pokedex_growth_rates,
  level       smallint not null check (level between 1 and 100),
  tokens      bigint not null check (tokens >= 0),
  primary key (growth_rate, level)
);

with totals as (
  select e.growth_rate,
         500000000::numeric * e.exp / m.exp as total
    from public.pokedex_experience_levels e
    join public.pokedex_experience_levels m on m.growth_rate = 'medium' and m.level = 100
   where e.level = 100
)
insert into public.coder_experience_levels (growth_rate, level, tokens)
select t.growth_rate, n,
       round(t.total * power((n - 1) / 99.0, ln(0.4) / ln(49.0 / 99)))
  from totals t, generate_series(1, 100) n;

-- The balance of the game, in one row. Changing a value changes what happens
-- from then on and nothing already earned: experience is stored, not derived.
create table public.coder_settings (
  id                  boolean primary key default true check (id),
  -- S: tokens that make one egg cycle. An egg needs its species'
  -- hatch_counter of them, as the games count an egg in cycles of steps;
  -- the egg itself counts tokens, as a Pokémon counts experience.
  tokens_per_cycle    integer not null check (tokens_per_cycle > 0),
  -- How much likelier a line the person has never had is to hatch.
  unowned_line_weight integer not null check (unowned_line_weight >= 1),
  -- An egg is shiny one time in this many.
  shiny_odds          integer not null check (shiny_odds >= 1)
);

insert into public.coder_settings values (true, 1000000, 5, 64);


-- ============================================================
-- coder_companions: an egg or a Pokémon, one row for its whole life. Hatching fills
-- hatched_at and level on the same row, and evolving changes species_id.
--
-- species_id is a form, not a species: a form change, such as Rotom's, is a
-- change to this column, and a form fixed at birth, such as an Unown's
-- letter, stays as it hatched.
--
-- invested_tokens is the ledger. What a person may still invest is every
-- token their machines have reported, less the sum of this column over their
-- companions, so it only ever grows and a row is never deleted except with its
-- account. A way to let a Pokémon go will have to keep what it was given.
--
-- markings are the games' six box marks, ● ▲ ■ ♥ ★ ◆ from the lowest bits up,
-- two bits each: 0 off, 1 blue, 2 red. The check refuses a mark set to 3.
-- ============================================================
create table public.coder_companions (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users on delete cascade,
  species_id      integer not null references public.pokedex_species,
  egg_kind        text not null references public.coder_egg_kinds,
  is_shiny        boolean not null,
  egg_tokens      bigint not null default 0 check (egg_tokens >= 0),
  exp             bigint not null default 0 check (exp >= 0),
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

create index on public.coder_companions (user_id);

create table public.coder_companion_ribbons (
  companion_id uuid not null references public.coder_companions on delete cascade,
  ribbon_id    text not null references public.coder_ribbons,
  received_at  timestamptz not null default now(),
  primary key (companion_id, ribbon_id)
);


-- ============================================================
-- coder_trainers: one row per person playing, made when they start.
--
-- It says which companion is the main one, the one claim() feeds, and naming
-- the owner beside it stops that being anyone else's. It is also the row
-- every change locks first: two tabs claiming at once would otherwise both
-- see the same balance and spend it twice.
-- ============================================================
create table public.coder_trainers (
  user_id           uuid primary key references auth.users on delete cascade,
  main_companion_id uuid not null,
  created_at        timestamptz not null default now(),
  foreign key (main_companion_id, user_id) references public.coder_companions (id, user_id)
);


-- ============================================================
-- Access. As elsewhere: everything away first, then only what the web needs.
-- A person's own rows are not granted at all; box() is how they are read,
-- because an egg's species must not reach the browser before it hatches.
-- ============================================================
revoke all on
  public.coder_egg_kinds, public.coder_egg_rarities, public.coder_egg_species, public.coder_experience_levels, public.coder_ribbons, public.coder_settings, public.coder_companions,
  public.coder_companion_ribbons, public.coder_trainers
  from anon, authenticated;

alter table public.coder_egg_kinds        enable row level security;
alter table public.coder_egg_rarities     enable row level security;
alter table public.coder_experience_levels enable row level security;
alter table public.coder_egg_species      enable row level security;
alter table public.coder_ribbons           enable row level security;
alter table public.coder_settings     enable row level security;
alter table public.coder_companions        enable row level security;
alter table public.coder_companion_ribbons enable row level security;
alter table public.coder_trainers          enable row level security;

grant select on public.coder_egg_kinds, public.coder_egg_rarities, public.coder_egg_species,
  public.coder_experience_levels, public.coder_ribbons, public.coder_settings to authenticated;

create policy "anyone signed in can read egg rarities" on public.coder_egg_rarities
  for select to authenticated using (true);
create policy "anyone signed in can read the experience curve" on public.coder_experience_levels
  for select to authenticated using (true);
create policy "anyone signed in can read the kinds of egg" on public.coder_egg_kinds
  for select to authenticated using (true);
create policy "anyone signed in can read what eggs hold" on public.coder_egg_species
  for select to authenticated using (true);
create policy "anyone signed in can read ribbons" on public.coder_ribbons
  for select to authenticated using (true);
create policy "anyone signed in can read the game's settings" on public.coder_settings
  for select to authenticated using (true);


-- ============================================================
-- roll_egg — a new egg for a person, drawn here and nowhere else.
--
-- Every row of coder_egg_species for the kind asked for is a candidate at its
-- rarity's weight. A family the person has never had, not even as an unhatched egg,
-- weighs unowned_line_weight times more, so a collection does not stall on
-- duplicates for years.
--
-- Not granted to anyone: start_game and receive_egg call it as its owner.
-- ============================================================
create function public.roll_egg(owner uuid, egg_kind text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  settings public.coder_settings;
  drawn integer;
  egg uuid;
begin
  select * into settings from public.coder_settings;

  with owned as (
    select distinct public.pokedex_first_form(c.species_id) as first_form
      from public.coder_companions c
     where c.user_id = owner
  ),
  weighted as (
    select g.species_id as id,
           r.weight * case when o.first_form is null then settings.unowned_line_weight else 1 end as weight
      from public.coder_egg_species g
      join public.coder_egg_rarities r on r.id = g.rarity
      left join owned o on o.first_form = g.species_id
     where g.egg_kind = roll_egg.egg_kind
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

  if drawn is null then
    raise exception 'no egg of kind % can hold anything', roll_egg.egg_kind;
  end if;

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny)
  values (owner, drawn, roll_egg.egg_kind, floor(random() * settings.shiny_odds) = 0)
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
  if exists (select 1 from public.coder_trainers t where t.user_id = caller) then
    return jsonb_build_object('outcome', 'already_started');
  end if;

  begin
    egg := public.roll_egg(caller, 'national');
    insert into public.coder_trainers (user_id, main_companion_id) values (caller, egg);
  exception when unique_violation then
    -- Another tab started at the same moment. Its egg stands, and this one
    -- goes back with the rest of the block.
    return jsonb_build_object('outcome', 'already_started');
  end;

  return jsonb_build_object('outcome', 'started', 'companion_id', egg);
end;
$$;


-- ============================================================
-- claim — invest tokens the person has not yet spent into the main companion.
--
--   {"companion_id": "...", "tokens": 62000000}
--
--   → {"outcome": "claimed", "tokens": 62000000, "level_before": 7,
--      "level_after": 21, "balance": "0"}
--   → {"outcome": "nothing", "balance": "0"}   nothing left, or nothing fits
--   → {"outcome": "invalid_amount"}            not a positive number
--   → {"outcome": "not_main"}
--   → {"outcome": "not_started"}
--
-- The screen asks for an amount, and this places as much of it as it can:
-- no more than the balance, and no more than the companion can still take,
-- which is the tokens an egg needs to hatch or a Pokémon needs for Lv.100. An
-- egg counts tokens as a Pokémon counts experience, one for one. "tokens" in
-- the answer is what was placed, which the screen counts up to. There is no
-- limit to a claim and no daily cap: a busy day earns everything it spent,
-- and watching it fill slowly is the screen's doing.
--
-- The companion is named even though only the main one may take tokens today,
-- so the screen can say which one it means: a main changed in another tab is
-- refused rather than fed by surprise, and sharing out to others later is a
-- change to this check alone.
--
-- The balance is a string for the reason usage() gives its total as one.
-- ============================================================
create function public.claim(companion_id uuid, tokens bigint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  settings public.coder_settings;
  main uuid;
  target record;
  balance bigint;
  room bigint;
  spent bigint;
  new_level smallint;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  select t.main_companion_id into main
    from public.coder_trainers t
   where t.user_id = caller
     for update;
  if not found then
    return jsonb_build_object('outcome', 'not_started');
  end if;
  if main <> claim.companion_id then
    return jsonb_build_object('outcome', 'not_main');
  end if;
  if claim.tokens is null or claim.tokens <= 0 then
    return jsonb_build_object('outcome', 'invalid_amount');
  end if;

  select * into settings from public.coder_settings;

  balance := (select coalesce(sum(r.tokens), 0) from public.usage_rollups r where r.user_id = caller)
           - (select coalesce(sum(c.invested_tokens), 0) from public.coder_companions c where c.user_id = caller);

  select c.id, c.egg_tokens, c.exp, c.level, c.hatched_at, p.hatch_counter, p.growth_rate
    into target
    from public.coder_companions c
    join public.pokedex_species p on p.id = c.species_id
   where c.id = main;

  if target.hatched_at is null then
    room := target.hatch_counter::bigint * settings.tokens_per_cycle - target.egg_tokens;
  else
    select e.tokens - target.exp into room
      from public.coder_experience_levels e
     where e.growth_rate = target.growth_rate and e.level = 100;
  end if;

  spent := greatest(0, least(claim.tokens, balance, room));
  if spent = 0 then
    return jsonb_build_object('outcome', 'nothing', 'balance', greatest(balance, 0)::text);
  end if;

  if target.hatched_at is not null then
    select max(e.level) into new_level
      from public.coder_experience_levels e
     where e.growth_rate = target.growth_rate and e.tokens <= target.exp + spent;
  end if;

  update public.coder_companions c
     set egg_tokens = c.egg_tokens + case when target.hatched_at is null then spent else 0 end,
         exp = c.exp + case when target.hatched_at is null then 0 else spent end,
         level = coalesce(new_level, c.level),
         invested_tokens = c.invested_tokens + spent
   where c.id = main;

  return jsonb_build_object(
    'outcome', 'claimed',
    'tokens', spent,
    'level_before', target.level,
    'level_after', coalesce(new_level, target.level),
    'balance', (balance - spent)::text);
end;
$$;


-- ============================================================
-- A companion of the caller's, locked along with their trainer row. Every
-- button below starts here, so each takes its turn with claim().
--
-- Not granted to anyone.
-- ============================================================
create function public.lock_companion(owner uuid, companion_id uuid)
returns public.coder_companions
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  found public.coder_companions;
begin
  if owner is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  perform 1 from public.coder_trainers t where t.user_id = owner for update;
  select * into found
    from public.coder_companions c
   where c.id = lock_companion.companion_id and c.user_id = owner
     for update;
  return found;
end;
$$;


-- ============================================================
-- hatch — an egg with all the tokens it needs becomes a Lv.1 Pokémon.
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
  egg public.coder_companions := public.lock_companion(auth.uid(), hatch.companion_id);
  needed bigint;
begin
  if egg.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if egg.hatched_at is not null then
    return jsonb_build_object('outcome', 'not_an_egg');
  end if;

  select p.hatch_counter::bigint * g.tokens_per_cycle into needed
    from public.pokedex_species p, public.coder_settings g
   where p.id = egg.species_id;
  if egg.egg_tokens < needed then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  update public.coder_companions c set hatched_at = now(), level = 1 where c.id = egg.id;
  return jsonb_build_object('outcome', 'hatched', 'species_id', egg.species_id, 'is_shiny', egg.is_shiny);
end;
$$;


-- ============================================================
-- level_up_evolution — the form a form becomes by level alone, and at which
-- level, or no row. species knows stones and trades too; the game uses
-- only this. evolve() acts on it and box() shows it, so the two agree.
--
-- Every family an egg can hold has one such next form, so none is chosen.
--
-- Not granted to anyone.
-- ============================================================
create function public.level_up_evolution(from_id integer)
returns table (id integer, min_level smallint)
language sql
stable
set search_path = ''
as $$
  select p.id, m.level
    from public.pokedex_species p
    join public.pokedex_evolution_methods m on m.id = p.evolution_method
   where p.evolves_from_id = from_id
     and m.id in (select public.level_only_methods())
   order by p.id
   limit 1;
$$;


-- ============================================================
-- evolve — a Pokémon at or past its evolution level becomes the next form.
--
--   → {"outcome": "evolved", "from": 4, "to": 5}
--   → {"outcome": "not_ready"} | {"outcome": "not_found"}
--
-- Waiting costs nothing: it keeps levelling, and can evolve whenever the
-- person says.
-- ============================================================
create function public.evolve(companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  pokemon public.coder_companions := public.lock_companion(auth.uid(), evolve.companion_id);
  next_form integer;
begin
  if pokemon.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  select e.id into next_form
    from public.level_up_evolution(pokemon.species_id) e
   where e.min_level <= pokemon.level;
  if next_form is null then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  update public.coder_companions c set species_id = next_form where c.id = pokemon.id;
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
  pokemon public.coder_companions := public.lock_companion(caller, receive_egg.companion_id);
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

  update public.coder_companions c set egg_received_at = now() where c.id = pokemon.id;
  egg := public.roll_egg(caller, 'national');
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
create function public.eligible_ribbons(pokemon public.coder_companions)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(r.id order by r.id), '{}')
    from public.coder_ribbons r
   where case r.id
           when 'level-100' then pokemon.level = 100
           else false
         end
     and not exists (
           select 1 from public.coder_companion_ribbons cr
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
  pokemon public.coder_companions := public.lock_companion(auth.uid(), receive_ribbon.companion_id);
begin
  if pokemon.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if not exists (select 1 from public.coder_ribbons r where r.id = receive_ribbon.ribbon_id) then
    return jsonb_build_object('outcome', 'unknown_ribbon');
  end if;
  if exists (select 1 from public.coder_companion_ribbons cr
              where cr.companion_id = pokemon.id and cr.ribbon_id = receive_ribbon.ribbon_id) then
    return jsonb_build_object('outcome', 'already_received');
  end if;
  if not receive_ribbon.ribbon_id = any (public.eligible_ribbons(pokemon)) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  insert into public.coder_companion_ribbons (companion_id, ribbon_id)
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
  chosen public.coder_companions := public.lock_companion(caller, set_main.companion_id);
begin
  if chosen.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  update public.coder_trainers t set main_companion_id = chosen.id where t.user_id = caller;
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
  chosen public.coder_companions := public.lock_companion(auth.uid(), set_markings.companion_id);
begin
  if chosen.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  -- The table's check refuses a mark set to 3, with 23514.
  update public.coder_companions c set markings = set_markings.markings where c.id = chosen.id;
  return jsonb_build_object('outcome', 'set');
end;
$$;


-- ============================================================
-- box — everything the person has, for the screen.
--
--   → {"started": true, "main_companion_id": "...", "balance": "123",
--      "eggs":    [{"id", "created_at", "tokens", "tokens_needed", "is_main", "markings"}],
--      "pokemon": [{"id", "species_id", "dex_no", "ko_name", "en_name", "sprites", "growth_rate",
--                   "types": [{"id", "ko_name", "en_name"}], "is_shiny", "level",
--                   "tokens", "level_tokens", "next_level_tokens", "max_tokens",
--                   "evolves_to": {"species_id", "ko_name", "en_name", "level"} | null,
--                   "can_evolve", "can_receive_egg",
--                   "ribbons": [{"id", "ko_name", "en_name", "received_at"}],
--                   "ribbons_waiting": [{"id", "ko_name", "en_name"}], "created_at", "hatched_at",
--                   "is_main", "markings"}]}
--   → {"started": false, "balance": "123"}
--
-- Names come in Korean and English; the screen picks one. dex_no is the
-- national pokedex's number.
--
-- Progress is in tokens, the one unit a person knows: an egg's and a
-- Pokémon's alike. "tokens" is where it stands; an egg needs tokens_needed,
-- and level_tokens and next_level_tokens bracket a Pokémon's level.
--
-- An egg says how many tokens it needs, which hints at what it holds, as the
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
           - (select coalesce(sum(c.invested_tokens), 0) from public.coder_companions c where c.user_id = caller);

  select t.main_companion_id into main from public.coder_trainers t where t.user_id = caller;
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
               'dex_no', dex.number,
               'ko_name', p.ko_name,
               'en_name', p.en_name,
               'sprites', p.sprites,
               'growth_rate', p.growth_rate,
               'types', (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                          order by t.id = p.type2)
                           from public.pokedex_types t where t.id in (p.type1, p.type2)),
               'is_shiny', c.is_shiny,
               'level', c.level,
               'tokens', c.exp,
               'level_tokens', here.tokens,
               'next_level_tokens', above.tokens,
               'max_tokens', top.tokens,
               'evolves_to', case when nxt.id is not null then
                   jsonb_build_object('species_id', nxt.id, 'ko_name', target.ko_name, 'en_name', target.en_name,
                                      'level', nxt.min_level) end,
               'can_evolve', coalesce(c.level >= nxt.min_level, false),
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
        left join lateral public.level_up_evolution(p.id) nxt on true
        left join public.pokedex_species target on target.id = nxt.id
        left join public.pokedex_entries dex on dex.dex = 'national' and dex.species_id = p.id
       where c.user_id = caller and c.hatched_at is not null), '[]'::jsonb));
end;
$$;


-- ============================================================
-- Who may call what. See the note in the account migration.
-- ============================================================
revoke execute on function
  public.roll_egg(uuid, text),
  public.lock_companion(uuid, uuid),
  public.level_only_methods(),
  public.level_up_evolution(integer),
  public.eligible_ribbons(public.coder_companions),
  public.start_game(),
  public.claim(uuid, bigint),
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
  public.claim(uuid, bigint),
  public.hatch(uuid),
  public.evolve(uuid),
  public.receive_egg(uuid),
  public.receive_ribbon(uuid, text),
  public.set_main(uuid),
  public.set_markings(uuid, smallint),
  public.box()
  to authenticated;
