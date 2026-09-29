-- Generation V in the eggs, and a Unova egg.
--
-- Generation V adds no baby to a family from before, so the eggs that hold
-- earlier generations keep what they hold, and a national egg adds
-- Generation V's families. A Unova egg holds what Black 2 and White 2's
-- pokedex lists: its 152 families, Generation V's 82 and 70 from before,
-- each of which already has a rarity. Black and White's lists Generation V
-- only, where every other region's lists some from before.
--
-- As before, every family hatches, and one whose next step needs more than a
-- level waits for the game to support it. Karrablast and Shelmet evolve by
-- trading for each other, which is not a level-up, so level_only_methods
-- needs no change.


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('unova', '하나 알', 'Unova Egg');

-- Sold as the other regional eggs are.
insert into public.coder_shop_items (id, item_id, egg_kind, price, position) values
  ('unova-egg', null, 'unova', 25000, 14);


-- ============================================================
-- Rarities for Generation V, by the same rules from how Black and White hand
-- them over: on the first routes is common, later, in one place or in
-- shaking grass is uncommon, a one-off or a low chance is rare, the starters
-- and the pseudo-legendaries are very rare, and the legendaries and
-- mythicals are mythic.
-- The fossils are rare, as Hoenn's and Sinnoh's are. Zorua, which Black and
-- White give only at an event, and Cryogonal, Alomomola and Druddigon, each
-- rare where they are found, are rare, and so is Axew, whose line ends as
-- strong as a pseudo-legendary's. Deino, whose line is one, is very rare.
-- Then by feel: Trubbish is common, Roggenrola uncommon, and Yamask,
-- Pawniard and Larvesta rare.
-- ============================================================
create temporary table new_rarity (slug text primary key, rarity text not null);
insert into new_rarity (slug, rarity) values
  ('patrat', 'common'), ('lillipup', 'common'), ('purrloin', 'common'), ('pidove', 'common'),
  ('blitzle', 'common'), ('woobat', 'common'), ('timburr', 'common'), ('sewaddle', 'common'),
  ('venipede', 'common'), ('trubbish', 'common'),

  ('pansage', 'uncommon'), ('pansear', 'uncommon'), ('panpour', 'uncommon'), ('munna', 'uncommon'),
  ('roggenrola', 'uncommon'), ('drilbur', 'uncommon'), ('audino', 'uncommon'), ('tympole', 'uncommon'),
  ('throh', 'uncommon'), ('sawk', 'uncommon'), ('cottonee', 'uncommon'), ('petilil', 'uncommon'),
  ('basculin-red-striped', 'uncommon'), ('sandile', 'uncommon'), ('darumaka', 'uncommon'),
  ('maractus', 'uncommon'), ('dwebble', 'uncommon'), ('scraggy', 'uncommon'), ('sigilyph', 'uncommon'),
  ('minccino', 'uncommon'), ('gothita', 'uncommon'), ('solosis', 'uncommon'), ('ducklett', 'uncommon'),
  ('vanillite', 'uncommon'), ('deerling-spring', 'uncommon'), ('emolga', 'uncommon'),
  ('karrablast', 'uncommon'), ('foongus', 'uncommon'), ('frillish-male', 'uncommon'),
  ('joltik', 'uncommon'), ('ferroseed', 'uncommon'), ('klink', 'uncommon'), ('tynamo', 'uncommon'),
  ('elgyem', 'uncommon'), ('litwick', 'uncommon'), ('cubchoo', 'uncommon'), ('shelmet', 'uncommon'),
  ('stunfisk', 'uncommon'), ('mienfoo', 'uncommon'), ('golett', 'uncommon'), ('bouffalant', 'uncommon'),
  ('rufflet', 'uncommon'), ('vullaby', 'uncommon'), ('heatmor', 'uncommon'), ('durant', 'uncommon'),

  ('tirtouga', 'rare'), ('archen', 'rare'), ('zorua', 'rare'), ('cryogonal', 'rare'),
  ('alomomola', 'rare'), ('druddigon', 'rare'), ('axew', 'rare'), ('yamask', 'rare'),
  ('pawniard', 'rare'), ('larvesta', 'rare'),

  ('snivy', 'very-rare'), ('tepig', 'very-rare'), ('oshawott', 'very-rare'), ('deino', 'very-rare'),

  ('victini', 'mythic'), ('cobalion', 'mythic'), ('terrakion', 'mythic'), ('virizion', 'mythic'),
  ('tornadus-incarnate', 'mythic'), ('thundurus-incarnate', 'mythic'), ('reshiram', 'mythic'),
  ('zekrom', 'mythic'), ('landorus-incarnate', 'mythic'), ('kyurem', 'mythic'),
  ('keldeo-ordinary', 'mythic'), ('meloetta-aria', 'mythic'), ('genesect', 'mythic');

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
  if (select count(*) from hatchable where egg_kind = 'unova') <> 152 then
    raise exception 'expected 152 families in Black 2 and White 2''s pokedex';
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
