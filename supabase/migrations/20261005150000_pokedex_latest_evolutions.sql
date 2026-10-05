-- The way the newest games evolve a form, where it is not the way
-- evolution_method says. evolution_method is the oldest game's way, which the
-- game here builds on: Magnezone at Mt. Coronet, as Diamond and Pearl have
-- it. The national pokedex shows the newest instead: a Thunder Stone, as
-- every game since Sword and Shield has it. Only forms whose newest way
-- differs have a row.
--
-- The rows come from the migration after this one, which
-- apps/pokedex-web/scripts/generate.ts writes.

create table public.pokedex_latest_evolutions (
  species_id       integer primary key references public.pokedex_species,
  evolution_method text not null references public.pokedex_evolution_methods
);

revoke all on public.pokedex_latest_evolutions from anon, authenticated;
alter table public.pokedex_latest_evolutions enable row level security;
grant select on public.pokedex_latest_evolutions to anon, authenticated;
create policy "anyone can read the newest ways to evolve" on public.pokedex_latest_evolutions
  for select to anon, authenticated using (true);
