-- Legends: Arceus evolves on two more things: a move used a number of times
-- in a style (Stantler becomes Wyrdeer after using Psyshield Bash twenty
-- times in the agile style), and a full moon, a fourth time of day (Ursaring
-- becomes Ursaluna with a Peat Block on a full-moon night). A method gets a
-- column for the move used and for how many times; the full moon joins day,
-- night and dusk.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

alter table public.pokedex_evolution_methods
  add column used_move      text references public.pokedex_moves,
  add column min_move_count smallint check (min_move_count > 0),
  drop constraint pokedex_evolution_methods_time_of_day_check,
  add constraint pokedex_evolution_methods_time_of_day_check
    check (time_of_day in ('day', 'night', 'dusk', 'full-moon')),
  drop constraint pokedex_evolution_methods_conditions_key,
  add constraint pokedex_evolution_methods_conditions_key
    unique nulls not distinct (trigger, level, item, held_item, min_happiness, time_of_day,
                               relative_physical_stats, min_beauty, chance, gender, known_move,
                               location, party_species_id, trade_species_id, party_type,
                               known_move_type, min_affection, needs_overworld_rain,
                               turn_upside_down, region, version, natures, min_damage_taken,
                               used_move, min_move_count);
