-- Scarlet and Violet evolve on two more things: steps walked with the
-- Pokémon out in Let's Go (Bramblin becomes Brambleghast after a thousand),
-- and a Union Circle, with other players (Finizen becomes Palafin at Lv.38
-- in one). A method gets a column for the steps and one for the Union
-- Circle.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

alter table public.pokedex_evolution_methods
  add column min_steps         smallint check (min_steps > 0),
  add column needs_multiplayer boolean not null default false,
  drop constraint pokedex_evolution_methods_conditions_key,
  add constraint pokedex_evolution_methods_conditions_key
    unique nulls not distinct (trigger, level, item, held_item, min_happiness, time_of_day,
                               relative_physical_stats, min_beauty, chance, gender, known_move,
                               location, party_species_id, trade_species_id, party_type,
                               known_move_type, min_affection, needs_overworld_rain,
                               turn_upside_down, region, version, natures, min_damage_taken,
                               used_move, min_move_count, min_steps, needs_multiplayer);
