-- The rest of Generation I in the eggs, and eggs that follow the pokedexes.
--
-- Every family can hatch now. Before, a family with a stone or a trade in it
-- was left out whole, so that a button and a level were all any of them ever
-- needed. But a Pokémon keeps levelling whether or not the game can evolve it
-- yet, and evolve() asks only that its level has been reached, so one raised
-- now evolves the day its way is supported. Until then it stays as it is.
--
-- An egg holds the first form as the pokedex of its own name sees it: what
-- the pokedex lists without what it evolves from. The national pokedex lists
-- everything, so a national egg holds every family's first form. The gen1
-- kind becomes kanto, which is what it meant; none was ever handed out.
--
-- The start and the Lv.50 egg stay national. A regional egg is here as a
-- kind for a shop to sell, and nothing hands one out yet.


delete from public.coder_egg_species where egg_kind = 'gen1';
delete from public.coder_egg_kinds where id = 'gen1';

insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('kanto', '관동 알', 'Kanto Egg');


-- ============================================================
-- Rarities for the families that join, by the rules the game started with:
-- from how Red and Green hand them over. On the first routes is common,
-- later or in one place is uncommon, a one-off or a low chance is rare.
--
-- A species already in an egg keeps its tier. At these weights, and a line
-- never had weighing five times more, half of all people have all 79 but
-- the mythic ones after about 150 eggs, and all of them after about 300.
-- ============================================================
create temporary table egg_rarity (slug text primary key, rarity text not null);
insert into egg_rarity (slug, rarity) values
  ('nidoran-f', 'common'), ('nidoran-m', 'common'), ('oddish', 'common'), ('bellsprout', 'common'),
  ('poliwag', 'common'), ('geodude', 'common'),

  ('vulpix', 'uncommon'), ('jigglypuff', 'uncommon'), ('growlithe', 'uncommon'), ('abra', 'uncommon'),
  ('machop', 'uncommon'), ('shellder', 'uncommon'), ('gastly', 'uncommon'), ('exeggcute', 'uncommon'),
  ('staryu', 'uncommon'),

  ('pikachu', 'rare'), ('clefairy', 'rare'), ('eevee', 'rare');

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
