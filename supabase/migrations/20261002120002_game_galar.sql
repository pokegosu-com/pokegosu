-- Generation VIII in the eggs, a Galar egg, Galarian forms, and the ways
-- Generation VIII evolves.
--
-- Generation VIII adds no baby to a family from before, so the eggs that
-- hold earlier generations keep what they hold, and a national egg adds
-- Generation VIII's families. A Galar egg holds what Sword and Shield's
-- pokedex lists, the Isle of Armor's and the Crown Tundra's with it: its 287
-- families, Generation VIII's 47 and 240 from before, each of which already
-- has a rarity.
--
-- A Galarian form hatches from a Galar egg in place of its default, as an
-- Alolan one does from an Alola egg. A national egg now hatches only
-- defaults: a region's form is its region's egg's, and Meowth, with an
-- Alolan and a Galarian form, would otherwise hatch as either two times in
-- three. A Pokémon becomes a form only in Galar, as Koffing becomes Galarian
-- Weezing, if it hatched from a Galar egg.
--
-- What Generation VIII asks that the game here cannot see, it asks another
-- way, as the ways before:
--
--   - Milcery's spin, holding a sweet, is the screen's: Milcery tapped five
--     times in a second spins round, and offers to evolve. The server cannot
--     see it, and takes it as done, as it does Inkay's console.
--   - Galarian Farfetch'd's three critical hits are a Leek, and Kubfu's
--     towers their scrolls, as in Scarlet and Violet.
--   - Galarian Yamask's damage under the Dusty Bowl's dolmen is a Ground
--     request done: the Dusty Bowl is a desert's.
--   - Toxel's nature is a draw at the time, as Tyrogue's stats are.
--
-- Galarian Meowth and Galarian Yamask evolve only as Galar has them, into
-- Perrserker and Runerigus, not Persian and Cofagrigus.


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('galar', '가라르 알', 'Galar Egg');

-- Sold as the other items and eggs are, each after its kind. Strawberry
-- Sweet is not: Milcery's spin asks for nothing here.
update public.coder_shop_items set position = position + 8 where egg_kind is not null;
insert into public.coder_shop_items (id, item_id, egg_kind, price, position) values
  ('tart-apple',         'tart-apple',         null, 5000, 31),
  ('sweet-apple',        'sweet-apple',        null, 5000, 32),
  ('cracked-pot',        'cracked-pot',        null, 5000, 33),
  ('galarica-cuff',      'galarica-cuff',      null, 5000, 34),
  ('galarica-wreath',    'galarica-wreath',    null, 5000, 35),
  ('stick',              'stick',              null, 5000, 36),
  ('scroll-of-darkness', 'scroll-of-darkness', null, 5000, 37),
  ('scroll-of-waters',   'scroll-of-waters',   null, 5000, 38),
  ('galar-egg',          null,                 'galar', 25000, 46);


-- ============================================================
-- Rarities for Generation VIII, by the rules Sun and Moon's were given:
-- on the first routes is common, later, in one place or on one version is
-- uncommon, a one-off or a low chance is rare, the starters and the
-- pseudo-legendaries are very rare, and the legendaries and mythicals are
-- mythic.
-- Toxel, a gift egg, Indeedee, a low chance, and the four fossils, each
-- restored from two halves, are rare, and so are Applin and Sinistea.
-- Duraludon is very rare beside Dreepy. Kubfu, a one-off gift and
-- legendary, is mythic.
-- ============================================================
create temporary table new_rarity (slug text primary key, rarity text not null);
insert into new_rarity (slug, rarity) values
  ('skwovet', 'common'), ('rookidee', 'common'), ('blipbug', 'common'), ('nickit', 'common'),
  ('gossifleur', 'common'), ('wooloo', 'common'), ('chewtle', 'common'), ('yamper', 'common'),

  ('rolycoly', 'uncommon'), ('arrokuda', 'uncommon'), ('sizzlipede', 'uncommon'), ('clobbopus', 'uncommon'),
  ('silicobra', 'uncommon'), ('cramorant', 'uncommon'), ('hatenna', 'uncommon'), ('impidimp', 'uncommon'),
  ('milcery', 'uncommon'), ('pincurchin', 'uncommon'), ('snom', 'uncommon'), ('cufant', 'uncommon'),
  ('morpeko-full-belly', 'uncommon'), ('falinks', 'uncommon'), ('stonjourner', 'uncommon'),
  ('eiscue-ice', 'uncommon'),

  ('toxel', 'rare'), ('indeedee-male', 'rare'), ('dracozolt', 'rare'), ('arctozolt', 'rare'),
  ('dracovish', 'rare'), ('arctovish', 'rare'), ('applin', 'rare'), ('sinistea-phony', 'rare'),

  ('grookey', 'very-rare'), ('scorbunny', 'very-rare'), ('sobble', 'very-rare'), ('dreepy', 'very-rare'),
  ('duraludon', 'very-rare'),

  ('zacian', 'mythic'), ('zamazenta', 'mythic'), ('eternatus', 'mythic'), ('kubfu', 'mythic'),
  ('zarude', 'mythic'), ('regieleki', 'mythic'), ('regidrago', 'mythic'), ('glastrier', 'mythic'),
  ('spectrier', 'mythic'), ('calyrex', 'mythic');

insert into public.coder_species_rarities (species_id, rarity)
select s.id, r.rarity from new_rarity r join public.pokedex_species s using (slug);

-- The first form of every family each egg's pokedex lists, in its default
-- form, as the Alola egg is filled.
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
  if (select count(*) from new_rarity) <> 47
     or exists (select 1 from new_rarity r
                 where not exists (select 1 from public.pokedex_species s where s.slug = r.slug))
     or exists (select 1 from new_rarity r join public.pokedex_species s using (slug)
                 where not exists (select 1 from hatchable h where h.id = s.id)) then
    raise exception 'every new rarity needs a species an egg can hold';
  end if;
  if (select count(*) from hatchable where egg_kind = 'galar') <> 287 then
    raise exception 'expected 287 families in Galar''s pokedexes';
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
-- The Galarian forms a Galar egg hatches in place of their defaults.
-- Galarian Mr. Mime is among them, though a Galar egg holds Mime Jr. rather
-- than Mr. Mime: it is still Mr. Mime as Galar has it.
-- ============================================================
insert into public.coder_egg_regional_forms (species_id, egg_kind)
select s.id, 'galar' from public.pokedex_species s
 where s.slug like '%-galar'
   and exists (select 1 from public.coder_egg_species g where g.species_id = s.form_of);

do $$
begin
  if (select count(*) from public.coder_egg_regional_forms where egg_kind = 'galar') <> 13 then
    raise exception 'expected Galarian Meowth, Ponyta, Slowpoke, Farfetch''d, Mr. Mime, Articuno, '
                    'Zapdos, Moltres, Corsola, Zigzagoon, Darumaka, Yamask and Stunfisk';
  end if;
end;
$$;


-- ============================================================
-- roll_egg — as before, but a region's form only from its region's egg:
-- a national egg hatches the default. A species whose female is a form of
-- its own, as Indeedee's is, hatches as her when it hatches female.
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
           where s.form_of = drawn and rf.egg_kind = roll_egg.egg_kind) f
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


-- ============================================================
-- level_up_ways — as before, and:
--
--   - Milcery's spin, which the screen asks for: spin marks it, as
--     upside_down marks Inkay's. Its sweet and its time of day are not
--     asked.
--   - Galarian Yamask's damage, by a Ground request done.
--   - Toxel's nature, a draw.
--   - A Galarian form takes no way of its species that Galar does not give
--     it: Galarian Meowth never becomes Persian.
--
-- Not granted to anyone.
-- ============================================================
drop function public.level_up_ways(public.coder_companions, smallint);
create function public.level_up_ways(pokemon public.coder_companions, hour smallint)
returns table (id integer, min_level smallint, ready boolean, drawn boolean, upside_down boolean,
               spin boolean, priority bigint)
language sql
stable
set search_path = ''
as $$
  select w.id, w.min_level, w.ready, w.drawn, w.upside_down, w.spin,
         row_number() over (order by w.ready desc, w.regional desc, w.affection desc, w.dusk desc, w.id)
    from (
      select p.id, m.level as min_level,
             coalesce(pokemon.level >= m.level, true)
               and (coalesce(m.min_happiness, m.min_affection) is null or public.friendly(pokemon))
               and public.at_time_of_day(case when m.trigger <> 'spin' then m.time_of_day end, hour)
               and public.at_time_of_day(case m.version when 'sun' then 'day' when 'moon' then 'night' end, hour)
               and (coalesce(mv.type, m.known_move_type) is null
                    or public.did_request(pokemon.id, coalesce(mv.type, m.known_move_type)))
               and (m.trigger <> 'take-damage' or public.did_request(pokemon.id, 'ground'))
               and (m.party_species_id is null or public.in_box(pokemon, m.party_species_id, null))
               and (m.party_type is null or public.in_box(pokemon, null, m.party_type)) as ready,
             m.chance is not null or m.relative_physical_stats is not null or m.natures is not null as drawn,
             m.turn_upside_down as upside_down,
             m.trigger = 'spin' as spin,
             m.region is not null as regional,
             m.min_affection is not null as affection,
             coalesce(m.time_of_day = 'dusk', false) as dusk
        from public.pokedex_species f
        join public.pokedex_species p
          on p.evolves_from_id = f.id
          or (p.evolves_from_id = f.form_of
              and not exists (select 1 from public.pokedex_species q
                               where coalesce(q.form_of, q.id) = coalesce(p.form_of, p.id)
                                 and q.evolves_from_id = f.id)
              and not exists (select 1 from public.coder_egg_regional_forms rf where rf.species_id = f.id))
          or (f.slug = 'rockruff' and p.slug = 'lycanroc-dusk')
        join public.pokedex_evolution_methods m on m.id = p.evolution_method
        left join public.pokedex_moves mv on mv.id = m.known_move
       where f.id = pokemon.species_id
         and ((m.trigger = 'level-up' and m.item is null and m.held_item is null
               and m.location is null and m.min_beauty is null and not m.needs_overworld_rain)
              or m.trigger in ('spin', 'take-damage'))
         and (m.gender is null or m.gender = pokemon.gender)
         and (m.region is null or m.region = pokemon.egg_kind)
         and (m.version is null or m.version in ('sun', 'moon'))
    ) w;
$$;


-- ============================================================
-- item_ways — as before, and a Leek in place of Galarian Farfetch'd's three
-- critical hits, and a scroll in place of each of Kubfu's towers.
--
-- Not granted to anyone.
-- ============================================================
create or replace function public.item_ways(pokemon public.coder_companions, hour smallint)
returns table (id integer, item text)
language sql
stable
set search_path = ''
as $$
  select distinct on (w.item) w.id, w.item
    from (
      select p.id, m.region,
             case
               when m.trigger = 'use-item' then m.item
               when m.trigger = 'trade' and f.slug = 'karrablast' then 'shelmet-shell'
               when m.trigger = 'trade' then coalesce(m.held_item, 'linking-cord')
               when m.held_item is not null then m.held_item
               when m.location is not null then l.item_id
               when m.min_beauty is not null then 'prism-scale'
               when m.needs_overworld_rain then 'damp-rock'
               when m.trigger = 'meltan-candies' then 'meltan-candy'
               when m.trigger = 'three-critical-hits' then 'stick'
               when m.trigger = 'tower-of-darkness' then 'scroll-of-darkness'
               when m.trigger = 'tower-of-waters' then 'scroll-of-waters'
             end as item
        from public.pokedex_species f
        join public.pokedex_species p on p.evolves_from_id = f.id
        join public.pokedex_evolution_methods m on m.id = p.evolution_method
        left join public.coder_location_items l on l.location = m.location
       where f.id = pokemon.species_id
         and (m.trigger in ('use-item', 'trade', 'meltan-candies', 'three-critical-hits',
                            'tower-of-darkness', 'tower-of-waters')
              or (m.trigger = 'level-up'
                  and (m.held_item is not null or m.location is not null
                       or m.min_beauty is not null or m.needs_overworld_rain)))
         and coalesce(pokemon.level >= m.level, true)
         and public.at_time_of_day(m.time_of_day, hour)
         and (m.gender is null or m.gender = pokemon.gender)
         and (m.region is null or m.region = pokemon.egg_kind)
         and m.version is null and m.known_move is null and m.party_species_id is null
         and (m.trade_species_id is null or f.slug = 'karrablast'
              or public.in_box(pokemon, m.trade_species_id, null))
    ) w
   where w.item is not null
   order by w.item, w.region is null, w.id;
$$;


-- ============================================================
-- box — as before, and evolves_to says whether Milcery's spin is asked for.
-- can_evolve is false for it, which the screen offers only once spun.
-- ============================================================
create or replace function public.box(time_zone text default 'UTC')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  hour smallint := public.local_hour(box.time_zone);
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
                   jsonb_build_object('species_id', case when not nxt.drawn then nxt.id end,
                                      'ko_name', case when not nxt.drawn then target.ko_name end,
                                      'en_name', case when not nxt.drawn then target.en_name end,
                                      'level', nxt.min_level,
                                      'upside_down', nxt.upside_down,
                                      'spin', nxt.spin) end,
               'can_evolve', coalesce(nxt.ready and not nxt.upside_down and not nxt.spin, false),
               'item_evolutions', coalesce((
                   select jsonb_agg(jsonb_build_object(
                            'species_id', e.id, 'ko_name', s.ko_name, 'en_name', s.en_name,
                            'item', jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                                       'sprite', i.sprite))
                          order by e.id)
                     from public.item_ways(c, hour) e
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
        left join lateral (select * from public.level_up_ways(c, hour) w order by w.priority limit 1) nxt on true
        left join public.pokedex_species target on target.id = nxt.id
        left join public.pokedex_entries dex on dex.dex = 'national' and dex.species_id = p.id
       where c.user_id = caller and c.hatched_at is not null), '[]'::jsonb));
end;
$$;


-- ============================================================
-- Who may call what. See the note in the account migration.
-- ============================================================
revoke execute on function public.level_up_ways(public.coder_companions, smallint) from public;
