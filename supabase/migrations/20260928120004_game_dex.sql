-- A person's own pokedex: every form they have had, and whether they have
-- had it shiny. The Pokédex marks each entry with it for whoever is signed in.
--
-- A companion is one row for its whole life and evolving changes its
-- species_id, so the box forgets what a Pokémon was. This remembers: a form
-- is written down when a Pokémon hatches as it or evolves into it, and stays
-- written down whatever that Pokémon becomes next. An egg is written down
-- only once it hatches, since what it holds is not shown before then.
--
-- It is kept by a trigger rather than by hatch() and evolve() themselves, so
-- any later way to change what a Pokémon is writes it down too.


-- ============================================================
-- coder_dex_entries: a form a person has had. shiny_caught_at is when they
-- first had it shiny, and null if they never have.
-- ============================================================
create table public.coder_dex_entries (
  user_id         uuid not null references auth.users on delete cascade,
  species_id      integer not null references public.pokedex_species,
  caught_at       timestamptz not null default now(),
  shiny_caught_at timestamptz,
  primary key (user_id, species_id)
);

revoke all on public.coder_dex_entries from anon, authenticated;
alter table public.coder_dex_entries enable row level security;


create function public.record_dex_entry()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.coder_dex_entries (user_id, species_id, shiny_caught_at)
  values (new.user_id, new.species_id, case when new.is_shiny then now() end)
  on conflict (user_id, species_id) do update
    set shiny_caught_at = coalesce(public.coder_dex_entries.shiny_caught_at, excluded.shiny_caught_at);
  return null;
end;
$$;

revoke execute on function public.record_dex_entry() from public;

create trigger record_dex_entry
  after update of hatched_at, species_id on public.coder_companions
  for each row
  when (new.hatched_at is not null
        and (old.hatched_at is null or old.species_id is distinct from new.species_id))
  execute function public.record_dex_entry();


-- ============================================================
-- What everyone has had so far, from what their Pokémon are now.
--
-- An evolution only goes forward, so what a Pokémon was is found by
-- following evolves_from_id back from what it is, as far as what its egg
-- could have held. A Kanto egg holds Pikachu, so a Pikachu from one was never
-- a Pichu; a national egg holds Pichu, so a Raichu from one was. When is not
-- known, so every stage takes the day its Pokémon hatched.
-- ============================================================
insert into public.coder_dex_entries (user_id, species_id, caught_at, shiny_caught_at)
with recursive stage as (
  select c.user_id, c.egg_kind, c.is_shiny, c.hatched_at, s.id, s.evolves_from_id,
         exists (select 1 from public.coder_egg_species g
                  where g.egg_kind = c.egg_kind and g.species_id = coalesce(s.form_of, s.id)) as from_egg
    from public.coder_companions c
    join public.pokedex_species s on s.id = c.species_id
   where c.hatched_at is not null
  union all
  select st.user_id, st.egg_kind, st.is_shiny, st.hatched_at, s.id, s.evolves_from_id,
         exists (select 1 from public.coder_egg_species g
                  where g.egg_kind = st.egg_kind and g.species_id = coalesce(s.form_of, s.id))
    from stage st
    join public.pokedex_species s on s.id = st.evolves_from_id
   where not st.from_egg
)
select user_id, id, min(hatched_at), min(hatched_at) filter (where is_shiny)
  from stage
 group by user_id, id;


-- ============================================================
-- my_dex — the forms the caller has had.
--
--   → [{"species_id": 25, "default_id": 25, "shiny": false, "shiny_front": null}, ...]
--
-- default_id is the species' default form, so a list that shows one tile a
-- species can mark it for any of its forms. shiny_front is the form's shiny
-- sprite, where it has been had shiny, for the list to show in its place.
-- ============================================================
create function public.my_dex()
returns table (species_id integer, default_id integer, shiny boolean, shiny_front text)
language sql
stable
security definer
set search_path = ''
as $$
  select d.species_id, coalesce(s.form_of, s.id), d.shiny_caught_at is not null,
         case when d.shiny_caught_at is not null then s.sprites ->> 'front_shiny' end
    from public.coder_dex_entries d
    join public.pokedex_species s on s.id = d.species_id
   where d.user_id = auth.uid()
   order by d.species_id;
$$;

revoke execute on function public.my_dex() from public;
grant execute on function public.my_dex() to authenticated;
