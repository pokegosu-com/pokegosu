-- Generation VI in the eggs, and a Kalos egg.
--
-- Generation VI adds no baby to a family from before, so the eggs that hold
-- earlier generations keep what they hold, and a national egg adds
-- Generation VI's families. A Kalos egg holds what X and Y's pokedex lists,
-- its Central, Coastal and Mountain parts together, with Diancie, Hoopa and
-- Volcanion after them: its 226 families, Generation VI's 37 and 189 from
-- before, each of which already has a rarity.
--
-- As before, every family hatches, and one whose next step needs more than a
-- level waits for the game to support it. Generation VI's new conditions ask
-- more than a level, so level_up_evolution leaves them out.


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('kalos', '칼로스 알', 'Kalos Egg');

-- Sold as the other regional eggs are.
insert into public.coder_shop_items (id, item_id, egg_kind, price, position) values
  ('kalos-egg', null, 'kalos', 25000, 15);


-- ============================================================
-- level_up_evolution — as before, and a level-up that asks for a type in the
-- party, a move's type known, affection, rain or the console upside down
-- still waits: Pancham, Sliggoo and Inkay stay as they are.
--
-- Not granted to anyone.
-- ============================================================
create or replace function public.level_up_evolution(from_id integer, gender text)
returns table (id integer, min_level smallint)
language sql
stable
set search_path = ''
as $$
  select p.id, m.level
    from public.pokedex_species f
    join public.pokedex_species p
      on p.evolves_from_id = f.id
      or (p.evolves_from_id = f.form_of
          and not exists (select 1 from public.pokedex_species q
                           where coalesce(q.form_of, q.id) = coalesce(p.form_of, p.id)
                             and q.evolves_from_id = f.id))
    join public.pokedex_evolution_methods m on m.id = p.evolution_method
   where f.id = from_id
     and m.trigger = 'level-up' and m.level is not null and m.item is null
     and m.held_item is null and m.min_happiness is null and m.time_of_day is null
     and m.relative_physical_stats is null and m.min_beauty is null and m.chance is null
     and m.known_move is null and m.location is null and m.party_species_id is null
     and m.party_type is null and m.known_move_type is null and m.min_affection is null
     and not m.needs_overworld_rain and not m.turn_upside_down
     and (m.gender is null or m.gender = level_up_evolution.gender)
   order by p.id
   limit 1;
$$;


-- ============================================================
-- Rarities for Generation VI, by the same rules from how X and Y hand them
-- over: on the first routes is common, later, in one place or on one
-- version is uncommon, a one-off or a low chance is rare, the starters and
-- the pseudo-legendaries are very rare, and the legendaries and mythicals
-- are mythic.
-- The fossils are rare, as every region's are. Hawlucha and Carbink, each
-- rare where they are found, are rare, and so is Noibat, found only late and
-- whose line ends strong. Goomy, whose line is a pseudo-legendary's, is very
-- rare.
-- ============================================================
create temporary table new_rarity (slug text primary key, rarity text not null);
insert into new_rarity (slug, rarity) values
  ('bunnelby', 'common'), ('fletchling', 'common'), ('scatterbug-icy-snow', 'common'),
  ('litleo', 'common'), ('flabebe-red', 'common'),

  ('skiddo', 'uncommon'), ('pancham', 'uncommon'), ('furfrou-natural', 'uncommon'),
  ('espurr', 'uncommon'), ('honedge', 'uncommon'), ('spritzee', 'uncommon'), ('swirlix', 'uncommon'),
  ('inkay', 'uncommon'), ('binacle', 'uncommon'), ('skrelp', 'uncommon'), ('clauncher', 'uncommon'),
  ('helioptile', 'uncommon'), ('dedenne', 'uncommon'), ('klefki', 'uncommon'), ('phantump', 'uncommon'),
  ('pumpkaboo-average', 'uncommon'), ('bergmite', 'uncommon'),

  ('tyrunt', 'rare'), ('amaura', 'rare'), ('hawlucha', 'rare'), ('carbink', 'rare'), ('noibat', 'rare'),

  ('chespin', 'very-rare'), ('fennekin', 'very-rare'), ('froakie', 'very-rare'), ('goomy', 'very-rare'),

  ('xerneas-active', 'mythic'), ('yveltal', 'mythic'), ('zygarde-50', 'mythic'), ('diancie', 'mythic'),
  ('hoopa', 'mythic'), ('volcanion', 'mythic');

insert into public.coder_species_rarities (species_id, rarity)
select s.id, r.rarity from new_rarity r join public.pokedex_species s using (slug);

-- The first form of every family each egg's pokedex lists, in its default
-- form, as the Sinnoh egg is filled.
create temporary table hatchable as
select k.id as egg_kind, s.id
  from public.coder_egg_kinds k
  join public.pokedex_entries e on e.dex = k.id
  join public.pokedex_species s on s.id = e.species_id
 where s.form_of is null
   and not exists (select 1 from public.pokedex_entries p
                    where p.dex = k.id and p.species_id = s.evolves_from_id);

do $$
begin
  if exists (select 1 from new_rarity r
              where not exists (select 1 from public.pokedex_species s where s.slug = r.slug))
     or exists (select 1 from new_rarity r join public.pokedex_species s using (slug)
                 where not exists (select 1 from hatchable h where h.id = s.id)) then
    raise exception 'every new rarity needs a species an egg can hold';
  end if;
  if (select count(*) from hatchable where egg_kind = 'kalos') <> 226 then
    raise exception 'expected 226 families in X and Y''s pokedex';
  end if;
  if exists (select 1 from public.coder_egg_species g
              where not exists (select 1 from hatchable h
                                 where h.egg_kind = g.egg_kind and h.id = g.species_id)) then
    raise exception 'no egg should lose any of what it holds';
  end if;
end;
$$;

-- A species without a rarity fails here, on the foreign key, rather than
-- going quiet.
insert into public.coder_egg_species (egg_kind, species_id)
select egg_kind, id from hatchable
on conflict (egg_kind, species_id) do nothing;

drop table hatchable, new_rarity;
