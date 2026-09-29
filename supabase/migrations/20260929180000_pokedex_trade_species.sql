-- Generation V evolves on one more thing: trading for a given species.
-- Karrablast becomes Escavalier traded for a Shelmet, and Shelmet becomes
-- Accelgor traded for a Karrablast. A method gets a nullable column for it,
-- as Generation IV's party species did.
--
-- Black 2 and White 2's pokedex starts at No.0, Victini, so a number can be 0.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

alter table public.pokedex_evolution_methods
  -- Deferred, as party_species_id is: species point at their methods too.
  add column trade_species_id integer references public.pokedex_species
                              deferrable initially deferred,
  drop constraint pokedex_evolution_methods_conditions_key,
  add constraint pokedex_evolution_methods_conditions_key
    unique nulls not distinct (trigger, level, item, held_item, min_happiness, time_of_day,
                               relative_physical_stats, min_beauty, chance, gender, known_move,
                               location, party_species_id, trade_species_id);

alter table public.pokedex_entries
  drop constraint pokedex_entries_number_check,
  add constraint pokedex_entries_number_check check (number >= 0);
