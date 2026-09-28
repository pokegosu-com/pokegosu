-- Generation IV in the eggs, and a Sinnoh egg.
--
-- Generation IV adds seven babies to families from before: Budew, Chingling,
-- Bonsly, Mime Jr., Happiny, Munchlax and Mantyke. A national egg holds them
-- in place of Roselia, Chimecho, Sudowoodo, Mr. Mime, Chansey, Snorlax and
-- Mantine. The Kanto, Johto and Hoenn eggs keep what they hold, since their
-- pokedexes list none of the new babies. Diamond and Pearl's pokedex lists
-- 151, Generation IV's and some from before, so a Sinnoh egg holds first
-- forms from all four.
--
-- As before, every family hatches, and one whose next step needs more than a
-- level waits for the game to support it.


-- ============================================================
-- level_only_methods — a level-up at a level, with nothing else asked. The
-- conditions Generation IV adds count as asking something: a gender, which
-- the game does not keep, a move known, a place, and another Pokémon in the
-- party. Burmy and Combee wait on the first, as Wurmple does on its
-- personality.
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
     and m.relative_physical_stats is null and m.min_beauty is null and m.chance is null
     and m.gender is null and m.known_move is null and m.location is null
     and m.party_species_id is null;
$$;


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('sinnoh', '신오 알', 'Sinnoh Egg');


-- ============================================================
-- Rarities for Generation IV, by the same rules from how Diamond and Pearl
-- hand them over: on the first routes is common, later, in one place or from
-- a Honey Tree is uncommon, a one-off or a low chance is rare, the starters
-- and Gible are very rare, and the legendaries and mythicals are mythic.
-- Then by feel, as before: Buneary and Glameow are common, and Spiritomb,
-- which takes 32 other players to meet, very rare.
-- Every baby is rare, Riolu included. The fossils are rare, as Hoenn's are.
--
-- A species already in an egg keeps its tier.
--
-- At these weights, and a line never had weighing five times more, half of
-- all people have every national species but the mythic ones after about 500
-- eggs, and all 247 after about 1,500; with Generation III it was about 410
-- and 1,130. A Sinnoh egg's 72 take about 130 and 290.
-- ============================================================
create temporary table new_rarity (slug text primary key, rarity text not null);
insert into new_rarity (slug, rarity) values
  ('starly', 'common'), ('bidoof', 'common'), ('kricketot', 'common'), ('shinx', 'common'),
  ('buizel', 'common'), ('shellos-west', 'common'), ('buneary', 'common'), ('glameow', 'common'),

  ('burmy-plant', 'uncommon'), ('combee', 'uncommon'), ('pachirisu', 'uncommon'),
  ('cherubi', 'uncommon'), ('drifloon', 'uncommon'), ('stunky', 'uncommon'), ('bronzor', 'uncommon'), ('chatot', 'uncommon'),
  ('hippopotas', 'uncommon'), ('skorupi', 'uncommon'), ('croagunk', 'uncommon'),
  ('carnivine', 'uncommon'), ('finneon', 'uncommon'), ('snover', 'uncommon'),

  ('cranidos', 'rare'), ('shieldon', 'rare'), ('rotom', 'rare'),
  ('budew', 'rare'), ('chingling', 'rare'), ('bonsly', 'rare'), ('mime-jr', 'rare'),
  ('happiny', 'rare'), ('munchlax', 'rare'), ('riolu', 'rare'), ('mantyke', 'rare'),

  ('turtwig', 'very-rare'), ('chimchar', 'very-rare'), ('piplup', 'very-rare'), ('gible', 'very-rare'),
  ('spiritomb', 'very-rare'),

  ('uxie', 'mythic'), ('mesprit', 'mythic'), ('azelf', 'mythic'), ('dialga', 'mythic'),
  ('palkia', 'mythic'), ('heatran', 'mythic'), ('regigigas', 'mythic'),
  ('giratina-altered', 'mythic'), ('cresselia', 'mythic'), ('phione', 'mythic'),
  ('manaphy', 'mythic'), ('darkrai', 'mythic'), ('shaymin-land', 'mythic'),
  ('arceus-normal', 'mythic');

insert into public.coder_species_rarities (species_id, rarity)
select s.id, r.rarity from new_rarity r join public.pokedex_species s using (slug);

create temporary table hatchable as
select k.id as egg_kind, s.id, s.slug
  from public.coder_egg_kinds k
  join public.pokedex_entries e on e.dex = k.id
  join public.pokedex_species s on s.id = e.species_id
 where not exists (select 1 from public.pokedex_entries p
                    where p.dex = k.id and p.species_id = s.evolves_from_id);

do $$
begin
  if exists (select 1 from new_rarity r
              where not exists (select 1 from public.pokedex_species s where s.slug = r.slug))
     or exists (select 1 from new_rarity r join public.pokedex_species s using (slug)
                 where not exists (select 1 from hatchable h where h.id = s.id)) then
    raise exception 'every new rarity needs a species an egg can hold';
  end if;
end;
$$;

delete from public.coder_egg_species g
 where not exists (select 1 from hatchable h where h.egg_kind = g.egg_kind and h.id = g.species_id);
-- A species without a rarity fails here, on the foreign key, rather than
-- going quiet.
insert into public.coder_egg_species (egg_kind, species_id)
select egg_kind, id from hatchable
on conflict (egg_kind, species_id) do nothing;

drop table hatchable, new_rarity;
