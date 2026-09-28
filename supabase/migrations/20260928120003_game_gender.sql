-- A Pokémon has a gender, as the games give it: drawn when its egg is,
-- by its species' ratio, and kept through every evolution. A genderless
-- species, such as Magnemite, has none.
--
-- The game can now take the evolutions that ask for one alongside a level:
-- a female Burmy becomes Wormadam in her cloak and a male one Mothim, and a
-- female Combee becomes Vespiquen. A male Combee never evolves, as in the
-- games.
--
-- Every companion there is gets its gender now, by the same draw. Burmy
-- and Combee never evolved before, so none is of the wrong gender for its
-- species.

alter table public.coder_companions
  add column gender text check (gender in ('female', 'male'));

-- gender_rate is in eighths female, and -1 for a genderless species.
create function public.draw_gender(species_id integer)
returns text
language sql
volatile
set search_path = ''
as $$
  select case when p.gender_rate < 0 then null
              when random() * 8 < p.gender_rate then 'female'
              else 'male' end
    from public.pokedex_species p
   where p.id = species_id;
$$;

update public.coder_companions c set gender = public.draw_gender(c.species_id);


-- ============================================================
-- roll_egg — as before, and the egg's gender with it.
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

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, gender)
  values (owner, drawn, roll_egg.egg_kind, floor(random() * settings.shiny_odds) = 0,
          public.draw_gender(drawn))
  returning id into egg;
  return egg;
end;
$$;



-- ============================================================
-- level_up_evolution — the form a Pokémon of this form and gender becomes by
-- a level, and at which level, or no row. A level-up asks nothing more, or
-- only a gender, which must be this one; anything else still waits.
--
-- A form evolves as the pokedex says, from the form of the same name. Where
-- what it becomes has no form that comes from it, it goes as its default
-- does: Mothim comes only from Plant Cloak Burmy in the pokedex, and a male
-- Burmy in any cloak becomes it.
--
-- Among what is left for one gender, none has two, so none is chosen.
--
-- It takes the gender, so it replaces the one that took only a form, and
-- level_only_methods(), which it no longer needs.
--
-- Not granted to anyone.
-- ============================================================
create function public.level_up_evolution(from_id integer, gender text)
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
     and (m.gender is null or m.gender = level_up_evolution.gender)
   order by p.id
   limit 1;
$$;


-- ============================================================
-- evolve — as before, by the Pokémon's gender too.
-- ============================================================
create or replace function public.evolve(companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  pokemon public.coder_companions := public.lock_companion(auth.uid(), evolve.companion_id);
  next_form integer;
begin
  if pokemon.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  select e.id into next_form
    from public.level_up_evolution(pokemon.species_id, pokemon.gender) e
   where e.min_level <= pokemon.level;
  if next_form is null then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  update public.coder_companions c set species_id = next_form where c.id = pokemon.id;
  return jsonb_build_object('outcome', 'evolved', 'from', pokemon.species_id, 'to', next_form);
end;
$$;


-- ============================================================
-- box — as before, with each Pokémon's gender, and what it evolves into by
-- it. An egg's stays hidden, as its species does.
-- ============================================================
create or replace function public.box()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  main uuid;
  balance bigint;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  balance := (select coalesce(sum(r.tokens), 0) from public.usage_rollups r where r.user_id = caller)
           - (select coalesce(sum(c.invested_tokens), 0) from public.coder_companions c where c.user_id = caller);

  select t.main_companion_id into main from public.coder_trainers t where t.user_id = caller;
  if not found then
    return jsonb_build_object('started', false, 'balance', balance::text);
  end if;

  return jsonb_build_object(
    'started', true,
    'main_companion_id', main,
    'balance', balance::text,
    'eggs', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'created_at', c.created_at,
               'tokens', c.egg_tokens,
               'tokens_needed', p.hatch_counter::bigint * g.tokens_per_cycle,
               'is_main', c.id = main,
               'markings', c.markings)
             order by c.created_at)
        from public.coder_companions c
        join public.pokedex_species p on p.id = c.species_id
        cross join public.coder_settings g
       where c.user_id = caller and c.hatched_at is null), '[]'::jsonb),
    'pokemon', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'species_id', p.id,
               'dex_no', dex.number,
               'ko_name', p.ko_name,
               'en_name', p.en_name,
               'sprites', p.sprites,
               'growth_rate', p.growth_rate,
               'types', (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                          order by t.id = p.type2)
                           from public.pokedex_types t where t.id in (p.type1, p.type2)),
               'is_shiny', c.is_shiny,
               'gender', c.gender,
               'level', c.level,
               'tokens', c.exp,
               'level_tokens', here.tokens,
               'next_level_tokens', above.tokens,
               'max_tokens', top.tokens,
               'evolves_to', case when nxt.id is not null then
                   jsonb_build_object('species_id', nxt.id, 'ko_name', target.ko_name, 'en_name', target.en_name,
                                      'level', nxt.min_level) end,
               'can_evolve', coalesce(c.level >= nxt.min_level, false),
               'can_receive_egg', c.level >= 50 and c.egg_received_at is null,
               'ribbons', coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'ko_name', r.ko_name, 'en_name', r.en_name,
                                                       'received_at', cr.received_at)
                                    order by cr.received_at)
                     from public.coder_companion_ribbons cr
                     join public.coder_ribbons r on r.id = cr.ribbon_id
                    where cr.companion_id = c.id), '[]'::jsonb),
               'ribbons_waiting', coalesce((
                   select jsonb_agg(jsonb_build_object('id', r.id, 'ko_name', r.ko_name, 'en_name', r.en_name) order by r.id)
                     from public.coder_ribbons r
                    where r.id = any (public.eligible_ribbons(c))), '[]'::jsonb),
               'created_at', c.created_at,
               'hatched_at', c.hatched_at,
               'is_main', c.id = main,
               'markings', c.markings)
             order by c.hatched_at)
        from public.coder_companions c
        join public.pokedex_species p on p.id = c.species_id
        cross join public.coder_settings g
        join public.coder_experience_levels here on here.growth_rate = p.growth_rate and here.level = c.level
        join public.coder_experience_levels top on top.growth_rate = p.growth_rate and top.level = 100
        left join public.coder_experience_levels above
          on above.growth_rate = p.growth_rate and above.level = c.level + 1
        left join lateral public.level_up_evolution(c.species_id, c.gender) nxt on true
        left join public.pokedex_species target on target.id = nxt.id
        left join public.pokedex_entries dex on dex.dex = 'national' and dex.species_id = p.id
       where c.user_id = caller and c.hatched_at is not null), '[]'::jsonb));
end;
$$;


drop function public.level_up_evolution(integer);
drop function public.level_only_methods();

-- Not granted to anyone; the game's functions run as their owner.
revoke execute on function
  public.draw_gender(integer),
  public.level_up_evolution(integer, text)
  from public;
