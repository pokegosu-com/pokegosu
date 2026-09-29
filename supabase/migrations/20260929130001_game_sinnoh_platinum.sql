-- A Sinnoh egg holds what Platinum's pokedex lists, with the seven
-- legendaries and mythicals it leaves out after it, as the Sinnoh pokedex now
-- does. Diamond and Pearl's left out 26 Generation IV species, so a Sinnoh
-- egg never hatched Rotom or eight of Generation IV's legendaries and
-- mythicals.
--
-- The rule is the one the Sinnoh egg began with: the first form of every
-- family the pokedex lists, in its default form. It adds 30, Magnemite,
-- Eevee, Rotom and Arceus among them, and takes none away. Each already has a
-- rarity, from another egg or from Generation IV's. An egg already drawn
-- keeps what it holds.

create temporary table hatchable as
select s.id
  from public.pokedex_entries e
  join public.pokedex_species s on s.id = e.species_id
 where e.dex = 'sinnoh'
   and s.form_of is null
   and not exists (select 1 from public.pokedex_entries p
                    where p.dex = 'sinnoh' and p.species_id = s.evolves_from_id);

do $$
begin
  if (select count(*) from hatchable) <> 102 then
    raise exception 'expected 102 families in Platinum''s pokedex and the seven after it';
  end if;
  if exists (select 1 from public.coder_egg_species g
              where g.egg_kind = 'sinnoh' and not exists (select 1 from hatchable h where h.id = g.species_id)) then
    raise exception 'a Sinnoh egg should lose none of what it holds';
  end if;
end;
$$;

-- A species without a rarity fails here, on the foreign key, rather than
-- going quiet.
insert into public.coder_egg_species (egg_kind, species_id)
select 'sinnoh', id from hatchable
on conflict (egg_kind, species_id) do nothing;

drop table hatchable;
