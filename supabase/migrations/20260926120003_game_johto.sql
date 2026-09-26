-- Generation II in the eggs, and a Johto egg.
--
-- The first form a national egg holds is now a baby where there is one:
-- Pichu, not Pikachu. A Kanto egg still holds Pikachu, since Kanto's pokedex
-- does not list Pichu. Johto's pokedex, Gold and Silver's, lists all 251, so
-- for now a Johto egg holds what a national one does; the two part when a
-- later generation comes in.
--
-- As with Generation I, every family hatches, and one whose next step needs
-- more than a level waits for the game to support it.


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


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('johto', '성도 알', 'Johto Egg');


-- ============================================================
-- Rarities for Generation II, by the same rules from how Gold and Silver
-- hand them over: on the first routes is common, later or in one place or by
-- Headbutt is uncommon, a one-off or a low chance is rare, the starters,
-- Larvitar, Togepi and Smeargle are very rare, and the legendaries and Celebi
-- are mythic; adjusted by feel, as Generation I's were. A baby
-- is as rare as what it grows into, so an egg is no likelier to hold Elekid
-- than Electabuzz.
--
-- A species already in an egg keeps its tier. At these weights, and a line
-- never had weighing five times more, half of all people have every national
-- species but the mythic ones after about 250 eggs, and all 129 after about
-- 620; with Generation I alone it was about 150 and 300.
-- ============================================================
create temporary table egg_rarity (slug text primary key, rarity text not null);
insert into egg_rarity (slug, rarity) values
  ('sentret', 'common'), ('hoothoot', 'common'), ('ledyba', 'common'), ('spinarak', 'common'),
  ('hoppip', 'common'), ('wooper', 'common'), ('chinchou', 'common'), ('remoraid', 'common'),
  ('sunkern', 'common'),

  ('mareep', 'uncommon'), ('natu', 'uncommon'), ('marill', 'uncommon'), ('aipom', 'uncommon'),
  ('murkrow', 'uncommon'), ('misdreavus', 'uncommon'), ('unown-a', 'uncommon'), ('wobbuffet', 'uncommon'),
  ('girafarig', 'uncommon'), ('pineco', 'uncommon'), ('gligar', 'uncommon'), ('snubbull', 'uncommon'),
  ('qwilfish', 'uncommon'), ('teddiursa', 'uncommon'), ('slugma', 'uncommon'), ('swinub', 'uncommon'),
  ('mantine', 'uncommon'), ('houndour', 'uncommon'), ('phanpy', 'uncommon'), ('stantler', 'uncommon'),
  ('miltank', 'uncommon'), ('sudowoodo', 'uncommon'), ('yanma', 'uncommon'), ('dunsparce', 'uncommon'),
  ('shuckle', 'uncommon'), ('heracross', 'uncommon'),
  ('igglybuff', 'uncommon'), ('smoochum', 'uncommon'), ('elekid', 'uncommon'), ('magby', 'uncommon'),

  ('sneasel', 'rare'), ('corsola', 'rare'), ('delibird', 'rare'), ('skarmory', 'rare'),
  ('pichu', 'rare'), ('cleffa', 'rare'), ('tyrogue', 'rare'),

  ('chikorita', 'very-rare'), ('cyndaquil', 'very-rare'), ('totodile', 'very-rare'),
  ('larvitar', 'very-rare'), ('togepi', 'very-rare'), ('smeargle', 'very-rare'),

  ('raikou', 'mythic'), ('entei', 'mythic'), ('suicune', 'mythic'), ('lugia', 'mythic'),
  ('ho-oh', 'mythic'), ('celebi', 'mythic');

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
