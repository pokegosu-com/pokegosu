-- Generation II evolves on more than a level and an item: an item held while
-- traded (Onix to Steelix on a Metal Coat), friendship (Golbat to Crobat),
-- friendship at a time of day (Eevee to Espeon by day, Umbreon by night), and
-- Attack against Defense (Tyrogue to one of three). A method gets a column for
-- each, all nullable, since most ask none of them.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

alter table public.pokedex_evolution_methods
  add column held_item               text references public.pokedex_items,
  add column min_happiness           smallint check (min_happiness between 0 and 255),
  add column time_of_day             text check (time_of_day in ('day', 'night')),
  -- 1 if Attack is higher than Defense, -1 if lower, 0 if the two are equal.
  add column relative_physical_stats smallint check (relative_physical_stats between -1 and 1),
  drop constraint pokedex_evolution_methods_trigger_level_item_key,
  add constraint pokedex_evolution_methods_conditions_key
    unique nulls not distinct (trigger, level, item, held_item, min_happiness, time_of_day, relative_physical_stats);
