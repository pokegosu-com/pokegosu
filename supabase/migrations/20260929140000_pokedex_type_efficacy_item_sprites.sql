-- The type chart, and a sprite for each item.
--
-- How much damage a move of one type does to a Pokémon of another: the type
-- chart, as PokéAPI has it today, Fairy included. A Pokémon of two types
-- takes the product of the two.
--
-- Every pair has a row, a neutral one at 100, so a missing row is never taken
-- to mean neutral. The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

create table public.pokedex_type_efficacy (
  attacking_type text not null references public.pokedex_types,
  defending_type text not null references public.pokedex_types,
  -- A percentage, as PokéAPI keeps it: 0, 50, 100 or 200.
  damage_factor  smallint not null check (damage_factor in (0, 50, 100, 200)),
  primary key (attacking_type, defending_type)
);


-- ============================================================
-- Access, as for the other pokedex tables: anyone can read it.
-- ============================================================
revoke all on public.pokedex_type_efficacy from anon, authenticated;

alter table public.pokedex_type_efficacy enable row level security;

grant select on public.pokedex_type_efficacy to anon, authenticated;

create policy "anyone can read the type chart" on public.pokedex_type_efficacy
  for select to anon, authenticated using (true);


-- ============================================================
-- An item's sprite, a path on pokedex-web as a species' sprites are, such as
-- "/sprites/items/fire-stone.png". The migration after this one fills it.
-- ============================================================
alter table public.pokedex_items add column sprite text;
