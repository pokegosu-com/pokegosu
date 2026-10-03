-- Hisui in the eggs, a Hisui egg, Hisuian forms, and the ways Legends:
-- Arceus evolves.
--
-- Of Hisui's species, only Enamorus starts a family; the rest come from
-- families already in. So the eggs that hold earlier generations keep what
-- they hold, and a national egg adds Enamorus. A Hisui egg holds what Legends:
-- Arceus's pokedex lists: its 111 families, Enamorus and 110 from before,
-- each of which already has a rarity but Enamorus.
--
-- A Hisuian form hatches from a Hisui egg in place of its default, as a
-- Galarian one does from a Galar egg, and so does White-Striped Basculin, the
-- Basculin Hisui has. A Pokémon becomes a form only in Hisui, as Quilava
-- becomes Hisuian Typhlosion, if it hatched from a Hisui egg. Stantler,
-- Scyther and Ursaring evolve only in Legends: Arceus too, but into species
-- of their own, which any egg's may become.
--
-- What Legends: Arceus asks that the game here cannot see, it asks another
-- way, as the ways before:
--
--   - Stantler's Psyshield Bash, used twenty times in the agile style, is a
--     Psychic request done, as knowing a move is a request of its type.
--     Hisuian Qwilfish knowing Barb Barrage, as Scarlet and Violet have it,
--     is a Poison one.
--   - White-Striped Basculin's 294 recoil damage is a Water request done, as
--     Galarian Yamask's damage is a Ground one.
--   - Ursaring's full moon is the real one: a Peat Block works on a night
--     within a day and a half of a full moon.


insert into public.coder_egg_kinds (id, ko_name, en_name) values
  ('hisui', '히스이 알', 'Hisui Egg');

-- Sold as the other items and eggs are, each after its kind.
update public.coder_shop_items set position = position + 2 where egg_kind is not null;
insert into public.coder_shop_items (id, item_id, egg_kind, price, position) values
  ('black-augurite', 'black-augurite', null, 5000, 39),
  ('peat-block',     'peat-block',     null, 5000, 40),
  ('hisui-egg',      null,             'hisui', 25000, 49);


-- ============================================================
-- Enamorus, one of the Forces of Nature beside Tornadus, Thundurus and
-- Landorus, is mythic as they are.
-- ============================================================
insert into public.coder_species_rarities (species_id, rarity)
select s.id, 'mythic' from public.pokedex_species s where s.slug = 'enamorus-incarnate';

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
  if (select count(*) from hatchable where egg_kind = 'hisui') <> 111 then
    raise exception 'expected 111 families in Hisui''s pokedex';
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

drop table hatchable;


-- ============================================================
-- The forms a Hisui egg hatches in place of their defaults.
-- ============================================================
insert into public.coder_egg_regional_forms (species_id, egg_kind)
select s.id, 'hisui' from public.pokedex_species s
 where (s.slug like '%-hisui' or s.slug = 'basculin-white-striped')
   and exists (select 1 from public.coder_egg_species g where g.species_id = s.form_of);

do $$
begin
  if (select count(*) from public.coder_egg_regional_forms where egg_kind = 'hisui') <> 6 then
    raise exception 'expected Hisuian Growlithe, Voltorb, Qwilfish, Sneasel and Zorua, '
                    'and White-Striped Basculin';
  end if;
end;
$$;


-- ============================================================
-- Helpers. None is granted to anyone.
-- ============================================================

-- Whether the moon is full at a moment, or within a day and a half of it:
-- its age from a known new moon, on the mean month of 29.53 days, is half a
-- month. The mean month strays from the real moon by under a day.
create function public.full_moon(at timestamptz)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select abs(mod((extract(epoch from at - timestamptz '2000-01-06 18:14:00+00') / 86400)::numeric,
                 29.530588853) - 29.530588853 / 2) <= 1.5;
$$;

-- at_time_of_day — as before, and a full moon is a night when the moon is
-- full. It reads the time, so it is no longer immutable.
create or replace function public.at_time_of_day(time_of_day text, hour smallint)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case at_time_of_day.time_of_day
           when 'day'       then hour between 6 and 17
           when 'night'     then hour not between 6 and 17
           when 'dusk'      then hour = 17
           when 'full-moon' then hour not between 6 and 17 and public.full_moon(now())
           else true
         end;
$$;


-- ============================================================
-- level_up_ways — as before, and:
--
--   - Stantler's Psyshield Bash in the agile style, by a request of the
--     move's type, Psychic.
--   - White-Striped Basculin's recoil damage, by a Water request done.
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
               and (coalesce(m.min_happiness, m.min_affection) is null or public.friendly(pokemon))
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
         and ((m.trigger = 'level-up' and m.item is null and m.held_item is null
               and m.location is null and m.min_beauty is null and not m.needs_overworld_rain)
              or m.trigger in ('spin', 'take-damage', 'agile-style-move', 'recoil-damage'))
         and (m.gender is null or m.gender = pokemon.gender)
         and (m.region is null or m.region = pokemon.egg_kind)
         and (m.version is null or m.version in ('sun', 'moon'))
    ) w;
$$;


-- ============================================================
-- Who may call what. See the note in the account migration.
-- ============================================================
revoke execute on function public.full_moon(timestamptz) from public;
