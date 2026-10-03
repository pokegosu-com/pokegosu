-- Generation IX in the eggs, a Paldea egg, Paldean forms, and the ways
-- Scarlet and Violet evolve.
--
-- Generation IX adds no baby to a family from before, so the eggs that hold
-- earlier generations keep what they hold, and a national egg adds
-- Generation IX's families. A Paldea egg holds what Scarlet and Violet's
-- pokedex lists, Kitakami's and Blueberry's with it: Generation IX's 72
-- families and the ones from before, each of which already has a rarity.
--
-- A Paldean form hatches from a Paldea egg in place of its default, as a
-- Galarian one does from a Galar egg: Paldean Wooper, and Paldean Tauros in
-- any of its three breeds. Squawkabilly hatches in any plumage, and
-- Tatsugiri in any of its three looks, as Unown does in any letter.
--
-- What Scarlet and Violet ask that the game here cannot see, it asks another
-- way, as the ways before:
--
--   - A thousand steps together in Let's Go, as Bramblin, Pawmo and Rellor
--     take, and Finizen's Union Circle with other players, are friendship,
--     reached as before on levels and hours as the partner.
--   - Primeape's twenty Rage Fists are a Ghost request done, as a move used
--     is a request of its type; so are Girafarig's Twin Beam a Psychic one,
--     Dunsparce's Hyper Drill a Normal one and Dipplin's Dragon Cheer a
--     Dragon one, as knowing a move is.
--   - The three Bisharp Bisharp must defeat, each leading others, are the
--     Leader's Crest they hold, and Gimmighoul's 999 coins one Gimmighoul
--     Coin, each used as a stone is.
--   - Maushold's levelling up in battle is levelling up.
--
-- Dunsparce becomes Three-Segment Dudunsparce, and Tandemaus a Family of
-- Three, one time in a hundred, as in the games; the draw weighs each by
-- its share as well as by whether the person has it.


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('paldea', '팔데아 알', 'Paldea Egg');

-- Sold as the other items and eggs are, each after its kind. The Masterpiece
-- Teacup is not: an Artisan Poltchageist is left out.
update public.coder_shop_items set position = position + 7 where egg_kind is not null;
insert into public.coder_shop_items (id, item_id, egg_kind, price, position) values
  ('syrupy-apple',        'syrupy-apple',        null, 5000, 41),
  ('metal-alloy',         'metal-alloy',         null, 5000, 42),
  ('auspicious-armor',    'auspicious-armor',    null, 5000, 43),
  ('malicious-armor',     'malicious-armor',     null, 5000, 44),
  ('unremarkable-teacup', 'unremarkable-teacup', null, 5000, 45),
  ('leaders-crest',       'leaders-crest',       null, 5000, 46),
  ('gimmighoul-coin',     'gimmighoul-coin',     null, 5000, 47),
  ('paldea-egg',          null,                  'paldea', 25000, 57);


-- ============================================================
-- Rarities for Generation IX, by the rules Sword and Shield's were given:
-- on the first routes is common, later, in one place or on one version is
-- uncommon, a one-off or a low chance is rare, the starters and the
-- pseudo-legendaries are very rare, and the legendaries and mythicals are
-- mythic.
-- Pawmi and Flittle are uncommon. Charcadet, Gimmighoul, Poltchageist,
-- Tatsugiri, Glimmet and Cyclizar are rare. Scarlet and Violet's fourteen
-- Paradox Pokémon are very rare beside Frigibax; the six of the DLC, each
-- met once as the legendaries are, are mythic with the Loyal Three, Ogerpon,
-- Terapagos and Pecharunt.
-- ============================================================
create temporary table new_rarity (slug text primary key, rarity text not null);
insert into new_rarity (slug, rarity) values
  ('lechonk', 'common'), ('tarountula', 'common'), ('nymble', 'common'), ('tandemaus', 'common'),
  ('fidough', 'common'), ('smoliv', 'common'), ('wattrel', 'common'), ('shroodle', 'common'),
  ('bramblin', 'common'), ('wiglett', 'common'),

  ('pawmi', 'uncommon'), ('flittle', 'uncommon'), ('squawkabilly-green-plumage', 'uncommon'),
  ('nacli', 'uncommon'), ('tadbulb', 'uncommon'), ('maschiff', 'uncommon'), ('toedscool', 'uncommon'),
  ('klawf', 'uncommon'), ('capsakid', 'uncommon'), ('rellor', 'uncommon'), ('tinkatink', 'uncommon'),
  ('bombirdier', 'uncommon'), ('finizen', 'uncommon'), ('varoom', 'uncommon'), ('orthworm', 'uncommon'),
  ('greavard', 'uncommon'), ('flamigo', 'uncommon'), ('cetoddle', 'uncommon'), ('veluza', 'uncommon'),
  ('dondozo', 'uncommon'),

  ('charcadet', 'rare'), ('gimmighoul-chest', 'rare'), ('poltchageist-counterfeit', 'rare'),
  ('tatsugiri-curly', 'rare'), ('glimmet', 'rare'), ('cyclizar', 'rare'),

  ('sprigatito', 'very-rare'), ('fuecoco', 'very-rare'), ('quaxly', 'very-rare'), ('frigibax', 'very-rare'),
  ('great-tusk', 'very-rare'), ('scream-tail', 'very-rare'), ('brute-bonnet', 'very-rare'),
  ('flutter-mane', 'very-rare'), ('slither-wing', 'very-rare'), ('sandy-shocks', 'very-rare'),
  ('iron-treads', 'very-rare'), ('iron-bundle', 'very-rare'), ('iron-hands', 'very-rare'),
  ('iron-jugulis', 'very-rare'), ('iron-moth', 'very-rare'), ('iron-thorns', 'very-rare'),
  ('roaring-moon', 'very-rare'), ('iron-valiant', 'very-rare'),

  ('wo-chien', 'mythic'), ('chien-pao', 'mythic'), ('ting-lu', 'mythic'), ('chi-yu', 'mythic'),
  ('koraidon-apex-build', 'mythic'), ('miraidon-ultimate-mode', 'mythic'), ('okidogi', 'mythic'),
  ('munkidori', 'mythic'), ('fezandipiti', 'mythic'), ('ogerpon', 'mythic'), ('terapagos', 'mythic'),
  ('pecharunt', 'mythic'), ('walking-wake', 'mythic'), ('iron-leaves', 'mythic'),
  ('gouging-fire', 'mythic'), ('raging-bolt', 'mythic'), ('iron-boulder', 'mythic'),
  ('iron-crown', 'mythic');

insert into public.coder_species_rarities (species_id, rarity)
select s.id, r.rarity from new_rarity r join public.pokedex_species s using (slug);

-- The first form of every family each egg's pokedex lists, in its default
-- form, as the Galar egg is filled.
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
  if (select count(*) from new_rarity) <> 72
     or exists (select 1 from new_rarity r
                 where not exists (select 1 from public.pokedex_species s where s.slug = r.slug))
     or exists (select 1 from new_rarity r join public.pokedex_species s using (slug)
                 where not exists (select 1 from hatchable h where h.id = s.id)) then
    raise exception 'every new rarity needs a species an egg can hold';
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
-- Squawkabilly's plumages and Tatsugiri's looks, which an egg hatches as
-- evenly beside the default.
-- ============================================================
insert into public.coder_egg_forms (species_id)
select s.id from public.pokedex_species s
 where s.form_of is not null
   and s.slug ~ '^(squawkabilly|tatsugiri)-';

do $$
begin
  if (select count(*) from public.coder_egg_forms f
        join public.pokedex_species s on s.id = f.species_id
       where s.slug ~ '^(squawkabilly|tatsugiri)-') <> 5 then
    raise exception 'expected 3 more Squawkabilly and 2 more Tatsugiri';
  end if;
end;
$$;


-- ============================================================
-- The Paldean forms a Paldea egg hatches in place of their defaults: one of
-- Tauros's three breeds, evenly, and Wooper.
-- ============================================================
insert into public.coder_egg_regional_forms (species_id, egg_kind)
select s.id, 'paldea' from public.pokedex_species s
 where s.slug like '%-paldea%'
   and exists (select 1 from public.coder_egg_species g
                where g.species_id = s.form_of and g.egg_kind = 'paldea');

do $$
begin
  if (select count(*) from public.coder_egg_regional_forms where egg_kind = 'paldea') <> 4 then
    raise exception 'expected Paldean Tauros''s three breeds, and Paldean Wooper';
  end if;
end;
$$;


-- ============================================================
-- level_up_ways — as before, and:
--
--   - Steps walked together and a Union Circle, by friendship.
--   - Primeape's Rage Fists, by a request of the move's type, Ghost.
--   - Maushold's levelling up in battle, as levelling up.
--
-- Not granted to anyone.
-- ============================================================
create or replace function public.level_up_ways(pokemon public.coder_companions, hour smallint)
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
               and ((coalesce(m.min_happiness, m.min_affection, m.min_steps) is null
                     and not m.needs_multiplayer)
                    or public.friendly(pokemon))
               and public.at_time_of_day(case when m.trigger <> 'spin' then m.time_of_day end, hour)
               and public.at_time_of_day(case m.version when 'sun' then 'day' when 'moon' then 'night' end, hour)
               and (coalesce(mv.type, used.type, m.known_move_type) is null
                    or public.did_request(pokemon.id, coalesce(mv.type, used.type, m.known_move_type)))
               and (m.trigger <> 'take-damage' or public.did_request(pokemon.id, 'ground'))
               and (m.trigger <> 'recoil-damage' or public.did_request(pokemon.id, 'water'))
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
        left join public.pokedex_moves used on used.id = m.used_move
       where f.id = pokemon.species_id
         and ((m.trigger in ('level-up', 'in-battle-level-up') and m.item is null and m.held_item is null
               and m.location is null and m.min_beauty is null and not m.needs_overworld_rain)
              or m.trigger in ('spin', 'take-damage', 'agile-style-move', 'recoil-damage', 'use-move'))
         and (m.gender is null or m.gender = pokemon.gender)
         and (m.region is null or m.region = pokemon.egg_kind)
         and (m.version is null or m.version in ('sun', 'moon'))
    ) w;
$$;


-- ============================================================
-- item_ways — as before, and a Leader's Crest in place of the three Bisharp
-- defeated, and a Gimmighoul Coin in place of 999.
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
               when m.trigger = 'three-defeated-bisharp' then 'leaders-crest'
               when m.trigger = 'gimmighoul-coins' then 'gimmighoul-coin'
             end as item
        from public.pokedex_species f
        join public.pokedex_species p on p.evolves_from_id = f.id
        join public.pokedex_evolution_methods m on m.id = p.evolution_method
        left join public.coder_location_items l on l.location = m.location
       where f.id = pokemon.species_id
         and (m.trigger in ('use-item', 'trade', 'meltan-candies', 'three-critical-hits',
                            'tower-of-darkness', 'tower-of-waters', 'three-defeated-bisharp',
                            'gimmighoul-coins')
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
-- evolve — as before, but a draw weighs each form by its share too, where
-- the games give one: Three-Segment Dudunsparce is 1 in 100 before whether
-- the person has it is weighed. Wurmple's halves weigh alike, as before.
-- ============================================================
create or replace function public.evolve(companion_id uuid, time_zone text default 'UTC')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  pokemon public.coder_companions := public.lock_companion(auth.uid(), evolve.companion_id);
  hour smallint := public.local_hour(evolve.time_zone);
  way record;
  next_form integer;
  left_behind uuid;
begin
  if pokemon.id is null or pokemon.hatched_at is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if public.at_work(pokemon.id) then
    return jsonb_build_object('outcome', 'working');
  end if;

  select * into way from public.level_up_ways(pokemon, hour) w where w.ready order by w.priority limit 1;
  if not found then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  next_form := way.id;
  if way.drawn then
    with weighted as (
      select w.id,
             coalesce(m.chance, 1)
               * case when public.owned_line(pokemon.user_id, w.id) = 0 then g.unowned_line_weight else 1 end
               as weight
        from public.level_up_ways(pokemon, hour) w
        join public.pokedex_species p on p.id = w.id
        join public.pokedex_evolution_methods m on m.id = p.evolution_method
       cross join public.coder_settings g
       where w.ready and w.drawn
    ),
    running as (
      select id, sum(weight) over (order by id) as upto, sum(weight) over () as total
        from weighted
    ),
    pick as (
      select random() * max(total) as point from running
    )
    select r.id into next_form
      from running r, pick
     where r.upto > pick.point
     order by r.id
     limit 1;
  end if;

  update public.coder_companions c set species_id = next_form where c.id = pokemon.id;
  left_behind := public.shed(pokemon);
  return jsonb_strip_nulls(jsonb_build_object(
    'outcome', 'evolved', 'from', pokemon.species_id, 'to', next_form, 'shed', left_behind));
end;
$$;
