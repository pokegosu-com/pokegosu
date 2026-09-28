-- A form a person has never had weighs more in an egg, as a family they
-- have never had does: unowned_line_weight times more. Someone with 27 of
-- Unown's letters draws the 28th five times likelier than any one they have,
-- once an egg has drawn Unown. How often an egg draws Unown is as before.
--
-- A form is had when a Pokémon of that person's began as it: East Sea
-- Gastrodon had East Sea Shellos. An egg counts, as it does for families.
-- A Mothim began as Plant Cloak Burmy whatever cloak it wore, since the
-- pokedex has Mothim come from that one only.


-- ============================================================
-- draw_form — which form of a species an egg holds: its default, or one of
-- the forms coder_egg_forms lists for it, each weighed by whether the owner
-- has had it.
--
-- -ln(1 - random()) / weight, least first, draws each in proportion to its
-- weight.
--
-- Not granted to anyone.
-- ============================================================
create function public.draw_form(owner uuid, species_id integer)
returns integer
language sql
volatile
set search_path = ''
as $$
  with had as (
    select distinct public.pokedex_first_form(c.species_id) as id
      from public.coder_companions c
     where c.user_id = owner
  )
  select f.id
    from (select draw_form.species_id as id
          union all
          select s.id from public.coder_egg_forms ef
            join public.pokedex_species s on s.id = ef.species_id
           where s.form_of = draw_form.species_id) f
   cross join public.coder_settings g
   order by -ln(1 - random())
            / case when f.id in (select id from had) then 1 else g.unowned_line_weight end
   limit 1;
$$;

revoke execute on function public.draw_form(uuid, integer) from public;


-- ============================================================
-- roll_egg — as before, with the form drawn by draw_form().
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

  drawn := public.draw_form(owner, drawn);

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, gender)
  values (owner, drawn, roll_egg.egg_kind, floor(random() * settings.shiny_odds) = 0,
          public.draw_gender(drawn))
  returning id into egg;
  return egg;
end;
$$;
