-- Generation III in the eggs, and a Hoenn egg.
--
-- A national egg's Marill becomes Azurill and its Wobbuffet Wynaut, the two
-- babies Generation III adds. A Johto egg keeps Marill and Wobbuffet, since
-- Gold and Silver's pokedex lists neither baby, so the Johto and national
-- eggs part here, as the migration that brought in Johto said they would.
-- Ruby, Sapphire and Emerald's pokedex lists 202, Generation III's and some
-- from before, so a Hoenn egg holds first forms from all three.
--
-- As before, every family hatches, and one whose next step needs more than a
-- level waits for the game to support it.


-- ============================================================
-- level_only_methods — a level-up at a level, with nothing else asked. The
-- conditions Generation III adds count as asking something: Feebas's beauty,
-- which the game does not keep, and Wurmple's half to Silcoon or Cascoon,
-- which hangs on a personality value the game does not keep either. Without
-- the second, Wurmple would have two ways by level alone, and
-- level_up_evolution would always take Silcoon.
-- ============================================================
create or replace function public.level_only_methods()
returns setof text
language sql
stable
set search_path = ''
as $$
  select m.id from public.pokedex_evolution_methods m
   where m.trigger = 'level-up' and m.level is not null and m.item is null
     and m.held_item is null and m.min_happiness is null and m.time_of_day is null
     and m.relative_physical_stats is null and m.min_beauty is null and m.chance is null;
$$;


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('hoenn', '호연 알', 'Hoenn Egg');


-- ============================================================
-- Rarities for Generation III, by the same rules from how Ruby, Sapphire and
-- Emerald hand them over: on the first routes is common, later or in one
-- place is uncommon, a one-off or a low chance is rare, the starters,
-- Feebas, Bagon and Beldum are very rare, and the legendaries, Jirachi and Deoxys are
-- mythic. A baby is as rare as what it grows into. The tiers were then
-- adjusted by feel, as Generation I's and II's were.
--
-- A species already in an egg keeps its tier, and one from before that only
-- a Hoenn egg holds as a first form takes the tier it has in another egg.
-- At these weights, and a line never had weighing five times more, half of
-- all people have every national species but the mythic ones after about 420
-- eggs, and all 202 after about 1,100; with Generation II it was about 250 and
-- 620. A Hoenn egg's 105 take about 190 and 480.
-- ============================================================
create temporary table egg_rarity (slug text primary key, rarity text not null);
insert into egg_rarity (slug, rarity) values
  ('poochyena', 'common'), ('zigzagoon', 'common'), ('wurmple', 'common'), ('seedot', 'common'),
  ('taillow', 'common'), ('wingull', 'common'), ('shroomish', 'common'), ('whismur', 'common'),
  ('spoink', 'common'),

  ('lotad', 'uncommon'), ('slakoth', 'uncommon'), ('nincada', 'uncommon'), ('makuhita', 'uncommon'),
  ('nosepass', 'uncommon'), ('skitty', 'uncommon'), ('sableye', 'uncommon'), ('mawile', 'uncommon'),
  ('aron', 'uncommon'), ('meditite', 'uncommon'), ('electrike', 'uncommon'), ('plusle', 'uncommon'),
  ('minun', 'uncommon'), ('volbeat', 'uncommon'), ('illumise', 'uncommon'), ('gulpin', 'uncommon'),
  ('carvanha', 'uncommon'), ('wailmer', 'uncommon'), ('numel', 'uncommon'), ('torkoal', 'uncommon'),
  ('spinda', 'uncommon'), ('cacnea', 'uncommon'), ('zangoose', 'uncommon'), ('seviper', 'uncommon'),
  ('lunatone', 'uncommon'), ('solrock', 'uncommon'), ('barboach', 'uncommon'), ('corphish', 'uncommon'),
  ('baltoy', 'uncommon'), ('shuppet', 'uncommon'), ('duskull', 'uncommon'), ('tropius', 'uncommon'),
  ('snorunt', 'uncommon'), ('spheal', 'uncommon'), ('clamperl', 'uncommon'), ('luvdisc', 'uncommon'),
  ('ralts', 'uncommon'), ('azurill', 'uncommon'), ('wynaut', 'uncommon'),

  ('surskit', 'rare'), ('roselia', 'rare'), ('trapinch', 'rare'), ('swablu', 'rare'),
  ('castform', 'rare'), ('kecleon', 'rare'), ('chimecho', 'rare'), ('absol', 'rare'),
  ('relicanth', 'rare'), ('lileep', 'rare'), ('anorith', 'rare'),

  ('treecko', 'very-rare'), ('torchic', 'very-rare'), ('mudkip', 'very-rare'), ('feebas', 'very-rare'),
  ('bagon', 'very-rare'), ('beldum', 'very-rare'),

  ('regirock', 'mythic'), ('regice', 'mythic'), ('registeel', 'mythic'), ('latias', 'mythic'),
  ('latios', 'mythic'), ('kyogre', 'mythic'), ('groudon', 'mythic'), ('rayquaza', 'mythic'),
  ('jirachi', 'mythic'), ('deoxys-normal', 'mythic');

create temporary table hatchable as
select k.id as egg_kind, s.id, s.slug,
       coalesce(r.rarity, (select g.rarity from public.coder_egg_species g
                            where g.species_id = s.id limit 1)) as rarity
  from public.coder_egg_kinds k
  join public.pokedex_entries e on e.dex = k.id
  join public.pokedex_species s on s.id = e.species_id
  left join egg_rarity r on r.slug = s.slug
 where not exists (select 1 from public.pokedex_entries p
                    where p.dex = k.id and p.species_id = s.evolves_from_id);

do $$
begin
  if exists (select 1 from hatchable where rarity is null)
     or exists (select slug from egg_rarity except select slug from hatchable) then
    raise exception 'every species an egg can hold needs a rarity, and every rarity such a species';
  end if;
end;
$$;

delete from public.coder_egg_species g
 where not exists (select 1 from hatchable h where h.egg_kind = g.egg_kind and h.id = g.species_id);
insert into public.coder_egg_species (egg_kind, species_id, rarity)
select egg_kind, id, rarity from hatchable
on conflict (egg_kind, species_id) do nothing;

drop table hatchable, egg_rarity;
