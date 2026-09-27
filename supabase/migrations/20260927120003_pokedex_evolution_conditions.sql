-- Generation III evolves on two more things: beauty (Feebas to Milotic, in
-- Ruby, Sapphire and Emerald), and a share decided by each Pokémon's
-- personality value (Wurmple to Silcoon for half, Cascoon for the other
-- half). A method gets a nullable column for each, as Generation II's did.
-- Nincada's Shedinja needs no column: it is a trigger of its own, shed.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

alter table public.pokedex_evolution_methods
  add column min_beauty smallint check (min_beauty between 0 and 255),
  -- How many of a hundred Pokémon go this way. Which ones is fixed for each,
  -- by its personality value, not drawn when it evolves.
  add column chance     smallint check (chance between 1 and 99),
  drop constraint pokedex_evolution_methods_conditions_key,
  add constraint pokedex_evolution_methods_conditions_key
    unique nulls not distinct (trigger, level, item, held_item, min_happiness, time_of_day,
                               relative_physical_stats, min_beauty, chance);
