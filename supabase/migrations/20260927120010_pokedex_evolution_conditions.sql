-- Generation IV evolves on four more things: a gender (Kirlia to Gallade for
-- males only, Burmy to Wormadam for females and Mothim for males), a move
-- known (Aipom to Ambipom on Double Hit), a place (Magneton to Magnezone at
-- Mt. Coronet, in Diamond and Pearl), and another Pokémon in the party
-- (Mantyke to Mantine with a Remoraid). A method gets a nullable column for
-- each, as Generations II and III's did, and moves and places get a table of
-- names, as items have.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

-- Moves, for now only those an evolution asks to know.
create table public.pokedex_moves (
  id      text primary key,
  ko_name text,
  en_name text
);

-- Places, for now only those an evolution happens at.
create table public.pokedex_locations (
  id      text primary key,
  ko_name text,
  en_name text
);

alter table public.pokedex_evolution_methods
  add column gender           text check (gender in ('female', 'male')),
  add column known_move       text references public.pokedex_moves,
  add column location         text references public.pokedex_locations,
  -- Deferred, since species point at their methods too, and the data
  -- migration writes the methods first.
  add column party_species_id integer references public.pokedex_species
                              deferrable initially deferred,
  drop constraint pokedex_evolution_methods_conditions_key,
  add constraint pokedex_evolution_methods_conditions_key
    unique nulls not distinct (trigger, level, item, held_item, min_happiness, time_of_day,
                               relative_physical_stats, min_beauty, chance, gender, known_move,
                               location, party_species_id);


-- ============================================================
-- Access, as for the other pokedex tables: anyone can read them.
-- ============================================================
revoke all on public.pokedex_moves, public.pokedex_locations from anon, authenticated;

alter table public.pokedex_moves     enable row level security;
alter table public.pokedex_locations enable row level security;

grant select on public.pokedex_moves, public.pokedex_locations to anon, authenticated;

create policy "anyone can read moves" on public.pokedex_moves
  for select to anon, authenticated using (true);
create policy "anyone can read locations" on public.pokedex_locations
  for select to anon, authenticated using (true);
