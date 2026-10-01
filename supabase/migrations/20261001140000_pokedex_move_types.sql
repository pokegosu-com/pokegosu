-- A move's type, which the Coder game asks for: a Pokémon that evolves
-- knowing a move does there by doing a request of that move's type, as
-- Piloswine knowing Ancient Power does by a Rock one.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

alter table public.pokedex_moves
  add column type text references public.pokedex_types;
