-- What is true of every Pokémon, and what each pokedex says about it. The
-- game and every other service read it and none of them owns it, so its
-- tables carry a pokedex_ prefix of their own rather than a schema, which the
-- Data API would need exposing.
--
-- pokedex_species holds the facts, one row per form: Rotom and Heat Rotom are two
-- rows, and so are Unown A and Unown B. Each row carries everything about its
-- form, because forms differ in exactly these things — types and stats, and
-- now and then a category or a capture rate.
--
-- pokedex_entries holds what each pokedex lists: which pokedex, which number, which form, and
-- what that pokedex writes about it. A number belongs to a pokedex rather
-- than to a species, since the Kanto and the national pokedex count
-- differently, and so does an entry's text, which each game writes anew.
--
-- Text comes a column per language, Korean and English for now. Each may be
-- null, so a language can be added before every row has its text.
--
-- The rows come from PokéAPI, written by apps/pokedex-web/scripts/generate.ts
-- into the migration after this one. Nothing else writes them.
--
-- It is reference data, and readable by anyone, signed in or not: a public
-- pokedex shows it to visitors. Only select is granted, on these tables only.


create table public.pokedex_types (
  id      text primary key,
  ko_name text,
  en_name text
);

-- PokéAPI's names. "medium" is what the games call Medium Fast.
create table public.pokedex_growth_rates (
  id text primary key
);

-- The games' own tables rather than the formulas behind them: Medium Slow's
-- formula goes negative at level 1, and the table is what the games use.
create table public.pokedex_experience_levels (
  growth_rate text not null references public.pokedex_growth_rates,
  level       smallint not null check (level between 1 and 100),
  exp         integer not null check (exp >= 0),
  primary key (growth_rate, level)
);

-- How an evolution is set off: levelling up, using an item, trading.
create table public.pokedex_evolution_triggers (
  id      text primary key,
  ko_name text,
  en_name text
);

-- Items, for now only those an evolution uses.
create table public.pokedex_items (
  id      text primary key,
  ko_name text,
  en_name text
);

-- One way to evolve: what sets it off, and what it asks. A level for most,
-- an item for a stone, nothing more for a plain trade. The id is made from
-- those, such as "level-up-16" or "use-item-thunder-stone", so the same way
-- is always the same row. A condition the games add later is a column here,
-- not on species.
create table public.pokedex_evolution_methods (
  id      text primary key,
  trigger text not null references public.pokedex_evolution_triggers,
  level   smallint check (level between 1 and 100),
  item    text references public.pokedex_items,
  unique nulls not distinct (trigger, level, item)
);


-- ============================================================
-- pokedex_species: one form of one Pokémon.
--
-- id is PokéAPI's form id, which for a species' default form is its national
-- dex number; slug is PokéAPI's name for it, for reading logs and diffs.
--
-- evolves_from_id and evolution_method say how this form is reached: from
-- which row, and which way — a level for Charmeleon, a Thunder Stone for
-- Raichu, a trade for Alakazam. Following
-- evolves_from_id up to a row with none finds the first form of a family, so
-- a family needs no number of its own. Pointing at a row rather than a
-- species is what lets Alolan Raichu evolve from Pikachu while Raichu does
-- too. An evolution from a form that is not in the table, such as Pichu into
-- Pikachu, is left out with it.
--
-- category is null for most, or baby, legendary or mythical, which the games
-- never combine. gender_rate is in eighths female, and -1 for a genderless
-- form. height is in decimetres and weight in hectograms, as the games keep
-- them.
--
-- sprites are paths on pokedex-web, such as "/sprites/pokemon/4.gif"; an app
-- puts its NEXT_PUBLIC_POKEDEX_URL in front. Which styles exist varies by form.
-- ============================================================
create table public.pokedex_species (
  id                integer primary key check (id > 0),
  slug              text not null unique,
  ko_name           text,
  en_name           text,
  ko_genus          text,
  en_genus          text,
  generation        smallint not null check (generation > 0),
  category          text check (category in ('baby', 'legendary', 'mythical')),

  type1             text not null references public.pokedex_types,
  type2             text references public.pokedex_types,
  hp                smallint not null check (hp > 0),
  attack            smallint not null check (attack > 0),
  defense           smallint not null check (defense > 0),
  special_attack    smallint not null check (special_attack > 0),
  special_defense   smallint not null check (special_defense > 0),
  speed             smallint not null check (speed > 0),
  height            smallint not null check (height > 0),
  weight            smallint not null check (weight > 0),

  growth_rate       text not null references public.pokedex_growth_rates,
  capture_rate      smallint not null check (capture_rate between 1 and 255),
  hatch_counter     smallint not null check (hatch_counter >= 0),
  gender_rate       smallint not null check (gender_rate between -1 and 8),

  evolves_from_id   integer references public.pokedex_species,
  evolution_method  text references public.pokedex_evolution_methods,

  sprites           jsonb not null default '{}',

  constraint evolution_is_whole check ((evolves_from_id is null) = (evolution_method is null)),
  constraint types_differ check (type2 is distinct from type1)
);

create index on public.pokedex_species (evolves_from_id);

-- The first form of a family: evolves_from_id followed to the end.
create function public.pokedex_first_form(species_id integer)
returns integer
language sql
stable
set search_path = ''
as $$
  with recursive up as (
    select s.id, s.evolves_from_id from public.pokedex_species s where s.id = species_id
    union all
    select s.id, s.evolves_from_id from public.pokedex_species s join up on s.id = up.evolves_from_id
  )
  select id from up where evolves_from_id is null;
$$;


-- ============================================================
-- pokedex_entries: one entry in one pokedex, of a kind in pokedex_kinds.
--
-- A number can hold several forms, as the national pokedex's 479 holds every
-- Rotom; is_default marks the one a list shows. A form is in a pokedex once.
-- ============================================================
create table public.pokedex_kinds (
  id      text primary key,
  ko_name text,
  en_name text
);

create table public.pokedex_entries (
  dex            text not null references public.pokedex_kinds,
  number         smallint not null check (number > 0),
  species_id     integer not null references public.pokedex_species,
  is_default     boolean not null,
  ko_description text,
  en_description text,
  primary key (dex, species_id)
);

create unique index pokedex_entries_one_default_per_number on public.pokedex_entries (dex, number) where is_default;
create index on public.pokedex_entries (species_id);


-- ============================================================
-- Access: select, for anyone, and nothing else.
-- ============================================================
revoke all on public.pokedex_types, public.pokedex_growth_rates, public.pokedex_experience_levels,
  public.pokedex_evolution_triggers, public.pokedex_items, public.pokedex_evolution_methods, public.pokedex_species, public.pokedex_kinds, public.pokedex_entries
  from anon, authenticated;

alter table public.pokedex_types              enable row level security;
alter table public.pokedex_growth_rates       enable row level security;
alter table public.pokedex_experience_levels  enable row level security;
alter table public.pokedex_evolution_triggers enable row level security;
alter table public.pokedex_items              enable row level security;
alter table public.pokedex_evolution_methods  enable row level security;
alter table public.pokedex_species            enable row level security;
alter table public.pokedex_kinds              enable row level security;
alter table public.pokedex_entries            enable row level security;

grant select on public.pokedex_types, public.pokedex_growth_rates, public.pokedex_experience_levels,
  public.pokedex_evolution_triggers, public.pokedex_items, public.pokedex_evolution_methods, public.pokedex_species, public.pokedex_kinds, public.pokedex_entries
  to anon, authenticated;

create policy "anyone can read types" on public.pokedex_types
  for select to anon, authenticated using (true);
create policy "anyone can read growth rates" on public.pokedex_growth_rates
  for select to anon, authenticated using (true);
create policy "anyone can read experience levels" on public.pokedex_experience_levels
  for select to anon, authenticated using (true);
create policy "anyone can read evolution triggers" on public.pokedex_evolution_triggers
  for select to anon, authenticated using (true);
create policy "anyone can read items" on public.pokedex_items
  for select to anon, authenticated using (true);
create policy "anyone can read evolution methods" on public.pokedex_evolution_methods
  for select to anon, authenticated using (true);
create policy "anyone can read species" on public.pokedex_species
  for select to anon, authenticated using (true);
create policy "anyone can read which pokedexes there are" on public.pokedex_kinds
  for select to anon, authenticated using (true);
create policy "anyone can read the pokedex" on public.pokedex_entries
  for select to anon, authenticated using (true);

-- Used by the game's functions, which run as their owner.
revoke execute on function public.pokedex_first_form(integer) from public;
