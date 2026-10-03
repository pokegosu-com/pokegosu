-- A national egg hatches a region's form again: it draws a species, then
-- one of the regions its forms are from, evenly, its default's with them.
-- Meowth hatches as itself, Alolan or Galarian, each one time in three, and
-- Tauros as itself one time in two, or in one of its three Paldean breeds.
-- A region's own egg still hatches only its region's form, and another
-- region's egg only the default.


-- ============================================================
-- roll_egg — as before, but a national egg draws a region for the form.
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
  region text;
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

  -- The region whose form it hatches as, or null for the default's.
  select r.region into region
    from (select null::text as region
          union
          select rf.egg_kind from public.coder_egg_regional_forms rf
            join public.pokedex_species s on s.id = rf.species_id
           where s.form_of = drawn) r
   where roll_egg.egg_kind = 'national' or r.region is null or r.region = roll_egg.egg_kind
   order by (r.region is not null and r.region = roll_egg.egg_kind) desc, random()
   limit 1;

  select f.id into drawn
    from (select drawn as id
           where region is null
          union all
          select s.id from public.coder_egg_forms ef
            join public.pokedex_species s on s.id = ef.species_id
           where s.form_of = drawn and region is null
          union all
          select s.id from public.coder_egg_regional_forms rf
            join public.pokedex_species s on s.id = rf.species_id
           where s.form_of = drawn and rf.egg_kind = region) f
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
