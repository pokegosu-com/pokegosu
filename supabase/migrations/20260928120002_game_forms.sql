-- An egg hatches some species in one of their forms: Unown as any letter,
-- Burmy in any cloak, Shellos from either sea. The games hand these over
-- that way, a letter or a cloak or a sea as it comes, so an egg draws one
-- evenly once it has drawn the species.
--
-- Every other form is left to how the games reach it, and an egg holds its
-- default: Rotom takes an appliance, Deoxys a meteorite, Giratina the
-- Griseous Orb, Shaymin the Gracidea, Arceus a plate, and Castform and
-- Cherrim change only in battle. Spiky-eared Pichu came to one event, and
-- never evolves.
--
-- A family is still a family whatever its form: someone with East Sea
-- Gastrodon has Shellos's line, and a Shellos egg weighs as one they had.


-- ============================================================
-- coder_egg_forms: the forms an egg can hatch as beside a species' default.
-- The species' default is what coder_egg_species lists and the draw weighs;
-- these share its chance evenly with it.
-- ============================================================
create table public.coder_egg_forms (
  species_id integer primary key references public.pokedex_species
);

insert into public.coder_egg_forms (species_id)
select s.id from public.pokedex_species s
 where s.form_of is not null
   and s.slug ~ '^(unown|burmy|shellos)-';

do $$
begin
  if (select count(*) from public.coder_egg_forms) <> 30 then
    raise exception 'expected 27 more Unown, 2 more Burmy and 1 more Shellos';
  end if;
  if exists (select 1 from public.coder_egg_forms f
               join public.pokedex_species s on s.id = f.species_id
              where not exists (select 1 from public.coder_egg_species g where g.species_id = s.form_of)) then
    raise exception 'a form an egg can hatch as needs a species an egg holds';
  end if;
end;
$$;


-- ============================================================
-- Access, as for the other tables the game reads from.
-- ============================================================
revoke all on public.coder_egg_forms from anon, authenticated;
alter table public.coder_egg_forms enable row level security;
grant select on public.coder_egg_forms to authenticated;
create policy "anyone signed in can read which forms an egg can hatch as" on public.coder_egg_forms
  for select to authenticated using (true);


-- ============================================================
-- roll_egg — as before, then a form of what it drew, and with a person's
-- families found from their default forms.
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

  select f.id into drawn
    from (select drawn as id
          union all
          select s.id from public.coder_egg_forms ef
            join public.pokedex_species s on s.id = ef.species_id
           where s.form_of = drawn) f
   order by random()
   limit 1;

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny)
  values (owner, drawn, roll_egg.egg_kind, floor(random() * settings.shiny_odds) = 0)
  returning id into egg;
  return egg;
end;
$$;
