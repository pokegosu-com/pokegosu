-- Generation VII evolves on three more things: a region (Pikachu becomes
-- Alolan Raichu with a Thunder Stone only in Alola), a game (Cosmoem becomes
-- Solgaleo in Sun and Lunala in Moon), and dusk, a third time of day
-- (Own Tempo Rockruff becomes Dusk Lycanroc). A method gets a column for the
-- region and the game, and each a table of names, as places have; dusk joins
-- day and night.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

-- Regions, for now only those an evolution happens in.
create table public.pokedex_regions (
  id      text primary key,
  ko_name text,
  en_name text
);

-- Games, for now only those an evolution happens in.
create table public.pokedex_versions (
  id      text primary key,
  ko_name text,
  en_name text
);

alter table public.pokedex_evolution_methods
  add column region  text references public.pokedex_regions,
  add column version text references public.pokedex_versions,
  drop constraint pokedex_evolution_methods_time_of_day_check,
  add constraint pokedex_evolution_methods_time_of_day_check
    check (time_of_day in ('day', 'night', 'dusk')),
  drop constraint pokedex_evolution_methods_conditions_key,
  add constraint pokedex_evolution_methods_conditions_key
    unique nulls not distinct (trigger, level, item, held_item, min_happiness, time_of_day,
                               relative_physical_stats, min_beauty, chance, gender, known_move,
                               location, party_species_id, trade_species_id, party_type,
                               known_move_type, min_affection, needs_overworld_rain,
                               turn_upside_down, region, version);


-- ============================================================
-- Access, as for the other pokedex tables: anyone can read them.
-- ============================================================
revoke all on public.pokedex_regions, public.pokedex_versions from anon, authenticated;

alter table public.pokedex_regions  enable row level security;
alter table public.pokedex_versions enable row level security;

grant select on public.pokedex_regions, public.pokedex_versions to anon, authenticated;

create policy "anyone can read regions" on public.pokedex_regions
  for select to anon, authenticated using (true);
create policy "anyone can read versions" on public.pokedex_versions
  for select to anon, authenticated using (true);
