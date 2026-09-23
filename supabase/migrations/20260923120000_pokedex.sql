-- The pokedex: what is true of every Pokémon, whatever the game makes of it.
--
-- One row per form, the finest grain the games have: Rotom and Heat Rotom are
-- two rows, and so are Unown A and Unown B. Each row carries everything about
-- its form, even where most forms of a species happen to agree, because some
-- do not: types and stats differ between varieties, and even a capture rate
-- can differ between forms. Only dex_no is shared by construction.
--
-- Names and texts are jsonb keyed by language — ko, en, ja, zh-Hans, zh-Hant,
-- fr, de, es, it — so a screen in any of them reads the same row. Korean and
-- English are always present.
--
-- The rows come from PokéAPI, written by apps/pokedex-web/scripts/generate.ts
-- into the migration after this one. Nothing else writes them.
--
-- It is reference data, and readable by anyone, signed in or not: a public
-- pokedex shows it to visitors. Only select is granted, on these tables only.


create table public.pokedex_types (
  id    text primary key,
  names jsonb not null check (names ? 'ko' and names ? 'en')
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


-- ============================================================
-- pokedex: one form of one Pokémon.
--
-- id is PokéAPI's form id, which for a species' default form is its national
-- dex number. is_default marks the one row that stands for its dex number in
-- a list.
--
-- evolves_from_id and evolution say how this form is reached: from which row,
-- and on what — {"trigger": "level-up", "min_level": 16}, or
-- {"trigger": "use-item", "item": {"id": "thunder-stone", "names": {...}}}.
-- Pointing at a row rather than a species is what lets Alolan Raichu evolve
-- from Pikachu while Raichu does too. An evolution from a form that is not in
-- the table, such as Pichu into Pikachu, is left out with it.
--
-- evolution_chain_id groups a family, as PokéAPI numbers them.
--
-- sprites are paths on pokedex-web, such as "/sprites/pokemon/4.gif"; an app
-- puts its NEXT_PUBLIC_POKEDEX_URL in front. Which styles exist varies by form.
--
-- gender_rate is in eighths female, and -1 for a genderless form. height is
-- in decimetres and weight in hectograms, as the games keep them.
-- ============================================================
create table public.pokedex (
  id                 integer primary key check (id > 0),
  slug               text not null unique,
  dex_no             smallint not null check (dex_no > 0),
  is_default         boolean not null,
  generation         smallint not null check (generation > 0),

  names              jsonb not null check (names ? 'ko' and names ? 'en'),
  genera             jsonb not null default '{}',
  descriptions       jsonb not null default '{}',

  type1              text not null references public.pokedex_types,
  type2              text references public.pokedex_types,
  hp                 smallint not null check (hp > 0),
  attack             smallint not null check (attack > 0),
  defense            smallint not null check (defense > 0),
  special_attack     smallint not null check (special_attack > 0),
  special_defense    smallint not null check (special_defense > 0),
  speed              smallint not null check (speed > 0),
  height             smallint not null check (height > 0),
  weight             smallint not null check (weight > 0),

  growth_rate        text not null references public.pokedex_growth_rates,
  capture_rate       smallint not null check (capture_rate between 1 and 255),
  hatch_counter      smallint not null check (hatch_counter >= 0),
  gender_rate        smallint not null check (gender_rate between -1 and 8),
  is_baby            boolean not null,
  is_legendary       boolean not null,
  is_mythical        boolean not null,

  evolution_chain_id smallint not null,
  evolves_from_id    integer references public.pokedex,
  evolution          jsonb check (evolution ? 'trigger'),

  sprites            jsonb not null default '{}',

  constraint evolution_is_whole check ((evolves_from_id is null) = (evolution is null)),
  constraint types_differ check (type2 is distinct from type1)
);

create unique index pokedex_one_default_per_dex_no on public.pokedex (dex_no) where is_default;
create index on public.pokedex (evolves_from_id);
create index on public.pokedex (evolution_chain_id);


-- ============================================================
-- Access: select, for anyone, and nothing else.
-- ============================================================
revoke all on public.pokedex, public.pokedex_types, public.pokedex_growth_rates,
  public.pokedex_experience_levels
  from anon, authenticated;

alter table public.pokedex                   enable row level security;
alter table public.pokedex_types             enable row level security;
alter table public.pokedex_growth_rates      enable row level security;
alter table public.pokedex_experience_levels enable row level security;

grant select on public.pokedex, public.pokedex_types, public.pokedex_growth_rates,
  public.pokedex_experience_levels
  to anon, authenticated;

create policy "anyone can read the pokedex" on public.pokedex
  for select to anon, authenticated using (true);
create policy "anyone can read types" on public.pokedex_types
  for select to anon, authenticated using (true);
create policy "anyone can read growth rates" on public.pokedex_growth_rates
  for select to anon, authenticated using (true);
create policy "anyone can read experience levels" on public.pokedex_experience_levels
  for select to anon, authenticated using (true);
