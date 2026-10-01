-- Generation VII in the eggs, an Alola egg, and Alolan forms.
--
-- Generation VII adds no baby to a family from before, so the eggs that hold
-- earlier generations keep what they hold, and a national egg adds
-- Generation VII's families. An Alola egg holds what Ultra Sun and Ultra
-- Moon's pokedex lists, with Meltan after it: its 210 families,
-- Generation VII's 55 and 155 from before, each of which already has a
-- rarity. No official source gives Meltan a generation; numbered after
-- Zeraora, it is taken as Generation VII's, and so Alola's.
--
-- An Alolan form is a species as Alola has it, so an egg hatches it as its
-- region does: an Alola egg hatches Alolan Rattata in place of Rattata, an
-- egg of any other region hatches Rattata, and a national egg either, evenly.
-- A form a Pokémon becomes only in Alola, as Pikachu becomes Alolan Raichu
-- with a Thunder Stone, it becomes if it hatched from an Alola egg; any
-- other becomes Raichu.
--
-- As before, every family hatches, and one whose next step needs more than a
-- level or a stone waits for the game to support it. A game is such a
-- condition: Cosmoem, which becomes Solgaleo in Sun and Lunala in Moon,
-- stays as it is, and so does Rockruff, whose every way asks a time of day.


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('alola', '알로라 알', 'Alola Egg');

-- Sold as the other regional eggs are. Alolan Sandshrew and Vulpix take an
-- Ice Stone, sold as the other stones are and beside them.
update public.coder_shop_items set position = position + 1 where egg_kind is not null;
insert into public.coder_shop_items (id, item_id, egg_kind, price, position) values
  ('ice-stone', 'ice-stone', null, 5000, 10),
  ('alola-egg', null, 'alola', 25000, 17);


-- ============================================================
-- coder_egg_regional_forms: the forms an egg of their region hatches in
-- place of their species' default, as Alolan Rattata is Rattata in Alola.
-- A national egg hatches either, evenly.
-- ============================================================
create table public.coder_egg_regional_forms (
  species_id integer primary key references public.pokedex_species,
  egg_kind   text not null references public.coder_egg_kinds
);

insert into public.coder_egg_regional_forms (species_id, egg_kind)
select s.id, 'alola' from public.pokedex_species s
 where s.slug like '%-alola'
   and exists (select 1 from public.coder_egg_species g where g.species_id = s.form_of);

do $$
begin
  if (select count(*) from public.coder_egg_regional_forms) <> 7 then
    raise exception 'expected Alolan Rattata, Sandshrew, Vulpix, Diglett, Meowth, Geodude and Grimer';
  end if;
end;
$$;

revoke all on public.coder_egg_regional_forms from anon, authenticated;
alter table public.coder_egg_regional_forms enable row level security;
grant select on public.coder_egg_regional_forms to authenticated;
create policy "anyone signed in can read which forms a region's egg hatches as" on public.coder_egg_regional_forms
  for select to authenticated using (true);


-- ============================================================
-- Rarities for Generation VII, by the same rules from how Sun and Moon hand
-- them over: on the first routes is common, later, in one place or on one
-- version is uncommon, a one-off or a low chance is rare, the starters and
-- the pseudo-legendaries are very rare, and the legendaries, mythicals and
-- Ultra Beasts are mythic.
-- Mimikyu, Drampa, Turtonator, Komala and Dhelmise, each a low chance where
-- it is found, are rare, and so is Minior, found only atop one mountain.
-- Jangmo-o, whose line is a pseudo-legendary's, is very rare. Type: Null, a
-- one-off gift made to fight the Ultra Beasts, is mythic beside them, and
-- Meltan, mythical, is mythic.
-- ============================================================
create temporary table new_rarity (slug text primary key, rarity text not null);
insert into new_rarity (slug, rarity) values
  ('pikipek', 'common'), ('yungoos', 'common'), ('grubbin', 'common'), ('cutiefly', 'common'),
  ('bounsweet', 'common'), ('mudbray', 'common'),

  ('crabrawler', 'uncommon'), ('oricorio-baile', 'uncommon'), ('rockruff', 'uncommon'),
  ('wishiwashi-solo', 'uncommon'), ('mareanie', 'uncommon'), ('dewpider', 'uncommon'),
  ('fomantis', 'uncommon'), ('morelull', 'uncommon'), ('salandit', 'uncommon'), ('stufful', 'uncommon'),
  ('comfey', 'uncommon'), ('oranguru', 'uncommon'), ('passimian', 'uncommon'), ('wimpod', 'uncommon'),
  ('sandygast', 'uncommon'), ('pyukumuku', 'uncommon'),
  ('togedemaru', 'uncommon'), ('bruxish', 'uncommon'),

  ('minior-red-meteor', 'rare'), ('mimikyu-disguised', 'rare'), ('drampa', 'rare'), ('turtonator', 'rare'),
  ('komala', 'rare'), ('dhelmise', 'rare'),

  ('rowlet', 'very-rare'), ('litten', 'very-rare'), ('popplio', 'very-rare'), ('jangmo-o', 'very-rare'),

  ('type-null', 'mythic'), ('tapu-koko', 'mythic'), ('tapu-lele', 'mythic'), ('tapu-bulu', 'mythic'), ('tapu-fini', 'mythic'),
  ('cosmog', 'mythic'), ('nihilego', 'mythic'), ('buzzwole', 'mythic'), ('pheromosa', 'mythic'),
  ('xurkitree', 'mythic'), ('celesteela', 'mythic'), ('kartana', 'mythic'), ('guzzlord', 'mythic'),
  ('necrozma', 'mythic'), ('magearna', 'mythic'), ('marshadow', 'mythic'), ('poipole', 'mythic'),
  ('stakataka', 'mythic'), ('blacephalon', 'mythic'), ('zeraora', 'mythic'), ('meltan', 'mythic');

insert into public.coder_species_rarities (species_id, rarity)
select s.id, r.rarity from new_rarity r join public.pokedex_species s using (slug);

-- Oricorio hatches in any of its four styles, as Shellos does from either
-- sea: the games hand it over in the style of the island it is found on.
insert into public.coder_egg_forms (species_id)
select s.id from public.pokedex_species s
 where s.form_of is not null and s.slug like 'oricorio-%';

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
  if (select count(*) from hatchable where egg_kind = 'alola') <> 210 then
    raise exception 'expected 210 families in Ultra Sun and Ultra Moon''s pokedex';
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


-- ============================================================
-- roll_egg — as before, and a form of its region in place of the default
-- from its region's egg, or either from a national egg.
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
           where roll_egg.egg_kind = 'national'
              or not exists (select 1 from public.coder_egg_regional_forms rf
                               join public.pokedex_species s on s.id = rf.species_id
                              where s.form_of = drawn and rf.egg_kind = roll_egg.egg_kind)
          union all
          select s.id from public.coder_egg_forms ef
            join public.pokedex_species s on s.id = ef.species_id
           where s.form_of = drawn
          union all
          select s.id from public.coder_egg_regional_forms rf
            join public.pokedex_species s on s.id = rf.species_id
           where s.form_of = drawn
             and (rf.egg_kind = roll_egg.egg_kind or roll_egg.egg_kind = 'national')) f
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
-- item_evolutions — as before, and a way only in a region for a Pokémon
-- from that region's egg, in place of the way anywhere else: an Alola egg's
-- Pikachu takes a Thunder Stone to Alolan Raichu, and any other to Raichu.
-- A way only in a game still waits.
--
-- Not granted to anyone.
-- ============================================================
drop function public.item_evolutions(integer, text);
create function public.item_evolutions(from_id integer, gender text, egg_kind text)
returns table (id integer, item text)
language sql
stable
set search_path = ''
as $$
  select distinct on (m.item) p.id, m.item
    from public.pokedex_species p
    join public.pokedex_evolution_methods m on m.id = p.evolution_method
   where p.evolves_from_id = from_id
     and m.trigger = 'use-item' and m.item is not null
     and (m.gender is null or m.gender = item_evolutions.gender)
     and m.time_of_day is null and m.held_item is null
     and m.location is null and m.known_move is null and m.party_species_id is null
     and (m.region is null or m.region = item_evolutions.egg_kind)
     and m.version is null
   order by m.item, m.region is null, p.id;
$$;

revoke execute on function public.item_evolutions(integer, text, text) from public;


-- ============================================================
-- use_item — as before, with the Pokémon's egg.
-- ============================================================
create or replace function public.use_item(companion_id uuid, item_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pokemon public.coder_companions := public.lock_companion(caller, use_item.companion_id);
  next_form integer;
begin
  if pokemon.id is null or pokemon.hatched_at is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if public.at_work(pokemon.id) then
    return jsonb_build_object('outcome', 'working');
  end if;
  if not exists (select 1 from public.coder_bag b
                  where b.user_id = caller and b.item_id = use_item.item_id and b.quantity > 0) then
    return jsonb_build_object('outcome', 'not_in_bag');
  end if;

  select e.id into next_form from public.item_evolutions(pokemon.species_id, pokemon.gender, pokemon.egg_kind) e
   where e.item = use_item.item_id;
  if next_form is null then
    return jsonb_build_object('outcome', 'no_effect');
  end if;

  update public.coder_bag b set quantity = b.quantity - 1
   where b.user_id = caller and b.item_id = use_item.item_id;
  update public.coder_companions c set species_id = next_form where c.id = pokemon.id;
  return jsonb_build_object('outcome', 'evolved', 'from', pokemon.species_id, 'to', next_form);
end;
$$;


-- ============================================================
-- box — as before, with each Pokémon's egg for its stones.
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
    'points', public.point_balance(caller),
    'bag', coalesce((
      select jsonb_agg(jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                          'sprite', i.sprite, 'quantity', b.quantity)
                       order by s.position, i.id)
        from public.coder_bag b
        join public.pokedex_items i on i.id = b.item_id
        left join public.coder_shop_items s on s.item_id = b.item_id
       where b.user_id = caller and b.quantity > 0), '[]'::jsonb),
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
               'form_slug', case when p.form_of is not null then p.slug end,
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
               'item_evolutions', coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'species_id', e.id, 'ko_name', s.ko_name, 'en_name', s.en_name,
                            'item', jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                                       'sprite', i.sprite))
                          order by e.id)
                     from public.item_evolutions(c.species_id, c.gender, c.egg_kind) e
                     join public.pokedex_species s on s.id = e.id
                     join public.pokedex_items i on i.id = e.item), '[]'::jsonb),
               'workplace_id', (select w.id from public.coder_workplaces w where w.companion_id = c.id),
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


-- ============================================================
-- level_up_evolution — as before, and a level-up only in a region or a game
-- still waits: Cosmoem stays as it is.
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
     and m.region is null and m.version is null
     and (m.gender is null or m.gender = level_up_evolution.gender)
   order by p.id
   limit 1;
$$;
