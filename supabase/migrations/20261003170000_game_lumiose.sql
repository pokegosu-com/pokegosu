-- A Lumiose egg.
--
-- It holds what the Lumiose pokedex lists, Lumiose City's and Hyperspace's
-- together: its 179 families, each of which already has a rarity, since
-- Legends: Z-A brings in no new species.
--
-- Every other egg hatches a region's form only from its region's egg. In
-- Legends: Z-A and its Mega Dimension, though, the regional forms of six of
-- those families are found beside their defaults, so a Lumiose egg hatches
-- either, evenly: Meowth as itself, Alolan or Galarian, and Slowpoke,
-- Farfetch'd, Stunfisk and Yamask as themselves or Galarian, and Qwilfish
-- as itself or Hisuian. Alolan Raichu and Marowak and Galarian Mr. Mime are
-- in the game only as gifts or wild, and its Mime Jr. becomes the default
-- Mr. Mime, so a Lumiose egg's Pikachu, Cubone and Mime Jr. evolve as any
-- other egg's.


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('lumiose', '미르 알', 'Lumiose Egg');

-- Sold as the other regional eggs are, after them.
insert into public.coder_shop_items (id, item_id, egg_kind, price, position) values
  ('lumiose-egg', null, 'lumiose', 25000, 58);


-- The first form of every family the Lumiose pokedex lists, in its default
-- form, as the Paldea egg is filled.
insert into public.coder_egg_species (egg_kind, species_id)
select 'lumiose', s.id
  from public.pokedex_entries e
  join public.pokedex_species s on s.id = e.species_id
 where e.dex = 'lumiose'
   and s.form_of is null
   and not exists (select 1 from public.pokedex_entries p
                    where p.dex = 'lumiose' and p.species_id = s.evolves_from_id);

do $$
begin
  if (select count(*) from public.coder_egg_species where egg_kind = 'lumiose') <> 179 then
    raise exception 'expected 179 families in the Lumiose pokedex';
  end if;
end;
$$;


-- ============================================================
-- coder_egg_kind_forms: forms an egg hatches beside their defaults, evenly,
-- as every egg does Oricorio's styles, but only that egg.
-- ============================================================
create table public.coder_egg_kind_forms (
  species_id integer not null references public.pokedex_species,
  egg_kind   text not null references public.coder_egg_kinds,
  primary key (species_id, egg_kind)
);

insert into public.coder_egg_kind_forms (species_id, egg_kind)
select s.id, 'lumiose' from public.pokedex_species s
 where s.slug in ('meowth-alola', 'meowth-galar', 'slowpoke-galar', 'farfetchd-galar',
                  'stunfisk-galar', 'yamask-galar', 'qwilfish-hisui');

do $$
begin
  if (select count(*) from public.coder_egg_kind_forms k
        join public.pokedex_species s on s.id = k.species_id
        join public.coder_egg_species g on g.species_id = s.form_of and g.egg_kind = k.egg_kind) <> 7 then
    raise exception 'expected seven regional forms of families a Lumiose egg holds';
  end if;
end;
$$;

revoke all on public.coder_egg_kind_forms from anon, authenticated;
alter table public.coder_egg_kind_forms enable row level security;
grant select on public.coder_egg_kind_forms to authenticated;
create policy "anyone signed in can read which forms an egg hatches beside their defaults" on public.coder_egg_kind_forms
  for select to authenticated using (true);


-- ============================================================
-- roll_egg — as before, and the forms an egg hatches beside their defaults.
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
  gender text;
  egg uuid;
begin
  select * into settings from public.coder_settings;

  with owned as (
    select distinct public.pokedex_first_form(coalesce(p.form_of, p.id)) as first_form
      from public.coder_companions c
      join public.pokedex_species p on p.id = c.species_id
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

  gender := public.draw_gender(drawn);

  select f.id into drawn
    from (select drawn as id
           where not exists (select 1 from public.coder_egg_regional_forms rf
                               join public.pokedex_species s on s.id = rf.species_id
                              where s.form_of = drawn and rf.egg_kind = roll_egg.egg_kind)
          union all
          select s.id from public.coder_egg_forms ef
            join public.pokedex_species s on s.id = ef.species_id
           where s.form_of = drawn
          union all
          select s.id from public.coder_egg_regional_forms rf
            join public.pokedex_species s on s.id = rf.species_id
           where s.form_of = drawn and rf.egg_kind = roll_egg.egg_kind
          union all
          select s.id from public.coder_egg_kind_forms kf
            join public.pokedex_species s on s.id = kf.species_id
           where s.form_of = drawn and kf.egg_kind = roll_egg.egg_kind) f
   order by random()
   limit 1;

  if gender = 'female' then
    select coalesce((select s.id from public.pokedex_species s
                      where s.form_of = drawn and s.slug like '%-female'), drawn)
      into drawn;
  end if;

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, gender)
  values (owner, drawn, roll_egg.egg_kind, floor(random() * settings.shiny_odds) = 0, gender)
  returning id into egg;
  return egg;
end;
$$;
