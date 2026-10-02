-- Generation VIII evolves on two more things: a nature (Toxel becomes Amped
-- or Low Key Toxtricity by its nature) and damage taken (Galarian Yamask
-- becomes Runerigus after taking 49 or more and passing under the Dusty
-- Bowl's dolmen). A method gets a column for each: the natures it takes, any
-- one of them, and the least damage.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

alter table public.pokedex_evolution_methods
  add column natures          text[] check (cardinality(natures) > 0),
  add column min_damage_taken smallint check (min_damage_taken > 0),
  drop constraint pokedex_evolution_methods_conditions_key,
  add constraint pokedex_evolution_methods_conditions_key
    unique nulls not distinct (trigger, level, item, held_item, min_happiness, time_of_day,
                               relative_physical_stats, min_beauty, chance, gender, known_move,
                               location, party_species_id, trade_species_id, party_type,
                               known_move_type, min_affection, needs_overworld_rain,
                               turn_upside_down, region, version, natures, min_damage_taken);
