-- Generation II in the game, and eggs that follow the pokedexes.
--
-- A national egg holds the first form of every family, babies included, so
-- Pichu hatches from it rather than Pikachu. A regional egg holds the first
-- form as its own pokedex sees it: whatever the pokedex lists without what
-- it evolves from. Kanto lists Pikachu and not Pichu, so a Kanto egg hatches
-- Pikachu. Johto's pokedex, Gold and Silver's, lists all 251, so for now a
-- Johto egg holds what a national one does; the two part when a later
-- generation comes in.
--
-- Every family can hatch now. Before, a family with a stone or a trade in it
-- was left out whole, so that a button and a level were all any of them ever
-- needed. Generation II hangs a trade or friendship off many Generation I
-- families, Zubat's and Onix's among them, and that rule would have taken
-- them out of every egg. What the game cannot do yet is evolve by anything
-- but a level, so a Pokémon whose next step needs more stays as it is until
-- it can.
--
-- The start and the Lv.50 egg stay national. Regional eggs are here as kinds
-- for a shop to sell, and nothing hands one out yet.


-- ============================================================
-- level_only_methods — a level-up at a level, with nothing else asked. The
-- conditions Generation II adds count as asking something: Tyrogue's
-- Lv.20 hangs on Attack against Defense, which the game does not keep.
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
     and m.relative_physical_stats is null;
$$;


-- ============================================================
-- Egg kinds: national, and a regional one per pokedex. The gen1 kind goes: it
-- was never handed out, and a Kanto egg is what it meant.
-- ============================================================
delete from public.coder_egg_species where egg_kind = 'gen1';
delete from public.coder_egg_kinds where id = 'gen1';

insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('kanto', '관동 알', 'Kanto Egg'),
  ('johto', '성도 알', 'Johto Egg');


-- ============================================================
-- Rarities, by hand. The tiers and the Generation I choices are the ones the
-- game started with; what is new follows the same rules. A Generation II
-- species goes by how Gold and Silver hand it over: on the first routes is
-- common, later or in one place or by Headbutt is uncommon, a one-off or a
-- low chance is rare, the starters and Larvitar are very rare, and the
-- legendaries and Celebi are mythic. A baby is as rare as what it grows into,
-- so an egg is no likelier to hold Elekid than Electabuzz.
--
-- At these weights, and a line never had weighing five times more, half of
-- all people have every national species but the mythic ones after about 250
-- eggs, and all 129 after about 610; with Generation I alone it was about 110
-- and 220. A Kanto egg's 79 take about 150 and 300.
--
-- Every species some egg can hold is here, and nothing else is: the check
-- below fails otherwise, rather than going quiet.
-- ============================================================
create temporary table egg_rarity (slug text primary key, rarity text not null);
insert into egg_rarity (slug, rarity) values
  -- Generation I, as the game started with.
  ('caterpie', 'common'), ('weedle', 'common'), ('pidgey', 'common'), ('rattata', 'common'),
  ('spearow', 'common'), ('ekans', 'common'), ('zubat', 'common'), ('diglett', 'common'),
  ('meowth', 'common'), ('goldeen', 'common'), ('magikarp', 'common'),

  ('sandshrew', 'uncommon'), ('paras', 'uncommon'), ('venonat', 'uncommon'), ('psyduck', 'uncommon'),
  ('mankey', 'uncommon'), ('tentacool', 'uncommon'), ('ponyta', 'uncommon'), ('slowpoke', 'uncommon'),
  ('magnemite', 'uncommon'), ('doduo', 'uncommon'), ('seel', 'uncommon'), ('grimer', 'uncommon'),
  ('onix', 'uncommon'), ('krabby', 'uncommon'), ('voltorb', 'uncommon'), ('cubone', 'uncommon'),
  ('koffing', 'uncommon'), ('rhyhorn', 'uncommon'), ('kangaskhan', 'uncommon'), ('scyther', 'uncommon'),
  ('jynx', 'uncommon'), ('electabuzz', 'uncommon'), ('magmar', 'uncommon'), ('pinsir', 'uncommon'),
  ('tauros', 'uncommon'),

  ('farfetchd', 'rare'), ('drowzee', 'rare'), ('hitmonlee', 'rare'), ('hitmonchan', 'rare'),
  ('lickitung', 'rare'), ('chansey', 'rare'), ('tangela', 'rare'), ('horsea', 'rare'),
  ('mr-mime', 'rare'), ('lapras', 'rare'), ('ditto', 'rare'), ('snorlax', 'rare'),

  ('bulbasaur', 'very-rare'), ('charmander', 'very-rare'), ('squirtle', 'very-rare'),
  ('porygon', 'very-rare'), ('omanyte', 'very-rare'), ('kabuto', 'very-rare'),
  ('aerodactyl', 'very-rare'), ('dratini', 'very-rare'),

  ('articuno', 'mythic'), ('zapdos', 'mythic'), ('moltres', 'mythic'), ('mewtwo', 'mythic'),
  ('mew', 'mythic'),

  -- Generation I families a stone or a trade used to keep out.
  ('nidoran-f', 'common'), ('nidoran-m', 'common'), ('oddish', 'common'), ('bellsprout', 'common'),
  ('poliwag', 'common'), ('geodude', 'common'),

  ('vulpix', 'uncommon'), ('jigglypuff', 'uncommon'), ('growlithe', 'uncommon'), ('abra', 'uncommon'),
  ('machop', 'uncommon'), ('shellder', 'uncommon'), ('gastly', 'uncommon'), ('exeggcute', 'uncommon'),
  ('staryu', 'uncommon'),

  ('pikachu', 'rare'), ('clefairy', 'rare'), ('eevee', 'rare'),

  -- Generation II.
  ('sentret', 'common'), ('hoothoot', 'common'), ('ledyba', 'common'), ('spinarak', 'common'),
  ('mareep', 'common'), ('hoppip', 'common'), ('wooper', 'common'),

  ('chinchou', 'uncommon'), ('natu', 'uncommon'), ('marill', 'uncommon'), ('aipom', 'uncommon'),
  ('sunkern', 'uncommon'), ('murkrow', 'uncommon'), ('misdreavus', 'uncommon'), ('unown-a', 'uncommon'),
  ('wobbuffet', 'uncommon'), ('girafarig', 'uncommon'), ('pineco', 'uncommon'), ('gligar', 'uncommon'),
  ('snubbull', 'uncommon'), ('qwilfish', 'uncommon'), ('sneasel', 'uncommon'), ('teddiursa', 'uncommon'),
  ('slugma', 'uncommon'), ('swinub', 'uncommon'), ('remoraid', 'uncommon'), ('mantine', 'uncommon'),
  ('houndour', 'uncommon'), ('phanpy', 'uncommon'), ('stantler', 'uncommon'), ('miltank', 'uncommon'),
  ('igglybuff', 'uncommon'), ('smoochum', 'uncommon'), ('elekid', 'uncommon'), ('magby', 'uncommon'),

  ('togepi', 'rare'), ('sudowoodo', 'rare'), ('yanma', 'rare'), ('dunsparce', 'rare'),
  ('shuckle', 'rare'), ('heracross', 'rare'), ('corsola', 'rare'), ('delibird', 'rare'),
  ('skarmory', 'rare'), ('smeargle', 'rare'), ('pichu', 'rare'), ('cleffa', 'rare'),
  ('tyrogue', 'rare'),

  ('chikorita', 'very-rare'), ('cyndaquil', 'very-rare'), ('totodile', 'very-rare'),
  ('larvitar', 'very-rare'),

  ('raikou', 'mythic'), ('entei', 'mythic'), ('suicune', 'mythic'), ('lugia', 'mythic'),
  ('ho-oh', 'mythic'), ('celebi', 'mythic');

-- What each kind can hold: every species the pokedex of the same name lists
-- without what it evolves from. The national pokedex lists everything, so
-- for a national egg that is every species with nothing to evolve from.
create temporary table hatchable as
select k.id as egg_kind, s.id, s.slug
  from public.coder_egg_kinds k
  join public.pokedex_entries e on e.dex = k.id
  join public.pokedex_species s on s.id = e.species_id
 where not exists (select 1 from public.pokedex_entries p
                    where p.dex = k.id and p.species_id = s.evolves_from_id);

do $$
begin
  if exists (select slug from hatchable except select slug from egg_rarity)
     or exists (select slug from egg_rarity except select slug from hatchable) then
    raise exception 'every species an egg can hold needs a rarity, and every rarity such a species';
  end if;
end;
$$;

delete from public.coder_egg_species;
insert into public.coder_egg_species (egg_kind, species_id, rarity)
select h.egg_kind, h.id, r.rarity from hatchable h join egg_rarity r using (slug);

drop table hatchable, egg_rarity;


-- ============================================================
-- level_up_evolution — as before; only what it can rely on has changed. An
-- egg's family may now have no next form by level alone, as Eevee's has none,
-- or one beside others it cannot reach, as Slowpoke's Slowbro sits beside
-- Slowking. None has two, since Tyrogue's three ask for more than a level, so
-- still none is chosen.
--
-- Not granted to anyone.
-- ============================================================
create or replace function public.level_up_evolution(from_id integer)
returns table (id integer, min_level smallint)
language sql
stable
set search_path = ''
as $$
  select p.id, m.level
    from public.pokedex_species p
    join public.pokedex_evolution_methods m on m.id = p.evolution_method
   where p.evolves_from_id = from_id
     and m.id in (select public.level_only_methods())
   order by p.id
   limit 1;
$$;


-- ============================================================
-- roll_egg — as before, but a family is matched to a family on both sides. A
-- Kanto egg's Pikachu is Pichu's family, which is what a person who hatched
-- Pichu already has, so it must not count as a line they never had.
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
      join public.coder_egg_rarities r on r.id = g.rarity
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
