-- A species' rarity is its own, and what an egg holds is only a list.
--
-- coder_egg_species gave every species its tier once per kind of egg that
-- holds it, and every kind always gave it the same one: each migration since
-- has copied a species' tier from whichever egg had it first. The tier now
-- lives once per species, in coder_species_rarities, and coder_egg_species
-- keeps which species each kind of egg holds. An egg can no longer make a
-- species rarer or commoner than another egg does; nothing ever has.


-- ============================================================
-- coder_species_rarities: how rare each species an egg can hold is.
-- ============================================================
create table public.coder_species_rarities (
  species_id integer primary key references public.pokedex_species,
  rarity     text not null references public.coder_egg_rarities
);

do $$
begin
  if exists (select species_id from public.coder_egg_species
              group by species_id having count(distinct rarity) > 1) then
    raise exception 'a species has a different rarity in different eggs';
  end if;
end;
$$;

insert into public.coder_species_rarities (species_id, rarity)
select distinct species_id, rarity from public.coder_egg_species;

-- A species an egg holds needs a rarity, so the list cannot name one the draw
-- would have no weight for.
alter table public.coder_egg_species
  drop column rarity,
  add constraint coder_egg_species_species_id_rarity_fkey
    foreign key (species_id) references public.coder_species_rarities;


-- ============================================================
-- Access, as for the other tables the game reads from.
-- ============================================================
revoke all on public.coder_species_rarities from anon, authenticated;
alter table public.coder_species_rarities enable row level security;
grant select on public.coder_species_rarities to authenticated;
create policy "anyone signed in can read how rare a species is" on public.coder_species_rarities
  for select to authenticated using (true);


-- ============================================================
-- roll_egg — as before, with the rarity read from the species.
-- ============================================================
create or replace function public.roll_egg(owner uuid, egg_kind text)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  settings public.coder_settings;
  drawn integer;
  egg uuid;
begin
  select * into settings from public.coder_settings;

  with owned as (
    select distinct public.pokedex_first_form(c.species_id) as first_form
      from public.coder_companions c
     where c.user_id = owner
  ),
  weighted as (
    select g.species_id as id,
           r.weight * case when o.first_form is null then settings.unowned_line_weight else 1 end as weight
      from public.coder_egg_species g
      join public.coder_species_rarities sr on sr.species_id = g.species_id
      join public.coder_egg_rarities r on r.id = sr.rarity
      left join owned o on o.first_form = public.pokedex_first_form(g.species_id)
     where g.egg_kind = roll_egg.egg_kind
  ),
  running as (
    select id, sum(weight) over (order by id) as upto, sum(weight) over () as total
      from weighted
  ),
  pick as (
    select random() * max(total) as point from running
  )
  select r.id into drawn
    from running r, pick
   where r.upto > pick.point
   order by r.id
   limit 1;

  if drawn is null then
    raise exception 'no egg of kind % can hold anything', roll_egg.egg_kind;
  end if;

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny)
  values (owner, drawn, roll_egg.egg_kind, floor(random() * settings.shiny_odds) = 0)
  returning id into egg;
  return egg;
end;
$$;
