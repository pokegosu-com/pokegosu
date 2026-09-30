-- Generation VI evolves on five more things: another Pokémon's type in the
-- party (Pancham to Pangoro with a Dark type), a move's type known and
-- affection (Eevee to Sylveon knowing a Fairy move), rain in the overworld
-- (Sliggoo to Goodra), and the console turned upside down (Inkay to
-- Malamar). A method gets a column for each, as Generation V's trade species
-- did: the types and affection nullable, rain and upside down a flag.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

alter table public.pokedex_evolution_methods
  add column party_type           text references public.pokedex_types,
  add column known_move_type      text references public.pokedex_types,
  add column min_affection        smallint,
  add column needs_overworld_rain boolean not null default false,
  add column turn_upside_down     boolean not null default false,
  drop constraint pokedex_evolution_methods_conditions_key,
  add constraint pokedex_evolution_methods_conditions_key
    unique nulls not distinct (trigger, level, item, held_item, min_happiness, time_of_day,
                               relative_physical_stats, min_beauty, chance, gender, known_move,
                               location, party_species_id, trade_species_id, party_type,
                               known_move_type, min_affection, needs_overworld_rain,
                               turn_upside_down);
