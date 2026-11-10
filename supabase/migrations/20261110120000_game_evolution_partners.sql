-- The evolutions that ask for another Pokémon ask less of the box.
--
-- Mantyke evolves with a Remoraid in the box, or with the Octillery one
-- becomes: a Pokémon the party asks for counts in any stage of its line. A
-- Mantyke of Lv.50 with neither may give a Remoraid egg in place of the
-- national one it would give, so the one it needs is a choice away. The egg
-- is shiny as often as any egg, and the Pokémon from it says Mantyke gave it.
--
-- Karrablast and Shelmet, which the games have trade for each other, each
-- take a Linking Cord, as every other trade does, with no other in the box.
-- Shelmet leaves no shell, and one left in a bag is gone with it.


-- ============================================================
-- Helpers. None is granted to anyone.
-- ============================================================

-- Whether the box holds another Pokémon, hatched, of a species's line in any
-- stage and form, or of a type. Remoraid's line is Remoraid and Octillery.
create or replace function public.in_box(pokemon public.coder_companions, species_id integer, type text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.coder_companions o
                   join public.pokedex_species s on s.id = o.species_id
                  where o.user_id = pokemon.user_id
                    and o.id is distinct from pokemon.id
                    and o.hatched_at is not null
                    and (in_box.species_id is null
                         or public.pokedex_first_form(coalesce(s.form_of, s.id))
                            = public.pokedex_first_form(in_box.species_id))
                    and (in_box.type is null or in_box.type in (s.type1, s.type2)));
$$;

-- The species the Pokémon's evolution needs in the box when the box holds
-- none of its line, as Mantyke's Remoraid, or null: the egg it may give in
-- place of a national one at Lv.50 holds the first stage of that line.
create function public.needed_egg(pokemon public.coder_companions)
returns integer
language sql
stable
set search_path = ''
as $$
  select public.pokedex_first_form(m.party_species_id)
    from public.pokedex_species f
    join public.pokedex_species p on p.evolves_from_id in (f.id, f.form_of)
    join public.pokedex_evolution_methods m on m.id = p.evolution_method
   where f.id = pokemon.species_id
     and m.party_species_id is not null
     and not public.in_box(pokemon, m.party_species_id, null)
   order by m.party_species_id
   limit 1;
$$;


-- ============================================================
-- item_ways — as before, but Karrablast and Shelmet each take a Linking
-- Cord, as any trade does, whatever else is in the box.
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
    ) w
   where w.item is not null
   order by w.item, w.region is null, w.id;
$$;


-- ============================================================
-- use_item — as before, but a Linking Cord used on Shelmet leaves nothing.
-- ============================================================
create or replace function public.use_item(companion_id uuid, item_id text, time_zone text default 'UTC')
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

  select e.id into next_form from public.item_ways(pokemon, public.local_hour(use_item.time_zone)) e
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
-- The Shelmet Shell, gone, from bags too.
-- ============================================================
delete from public.coder_bag where item_id = 'shelmet-shell';
delete from public.pokedex_items where id = 'shelmet-shell';


-- ============================================================
-- receive_egg — as before, or, given the species needed_egg names, an egg
-- of it in place of the national one. Mantyke gives it, and the Pokémon
-- from it says so.
--
--   → {"outcome": "received", "companion_id": "…"}
--   → {"outcome": "received", "companion_id": "…", "species": {"ko_name": "총어", …}}
--   → {"outcome": "not_offered"}   that species is not one it may give
-- ============================================================
drop function public.receive_egg(uuid);
create function public.receive_egg(companion_id uuid, species_id integer default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pokemon public.coder_companions := public.lock_companion(caller, receive_egg.companion_id);
  egg uuid;
  gender text;
  drawn integer := receive_egg.species_id;
begin
  if pokemon.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if public.at_work(pokemon.id) then
    return jsonb_build_object('outcome', 'working');
  end if;
  if pokemon.egg_received_at is not null then
    return jsonb_build_object('outcome', 'already_received');
  end if;
  if coalesce(pokemon.level, 0) < 50 then
    return jsonb_build_object('outcome', 'not_ready');
  end if;
  if drawn is not null and drawn is distinct from public.needed_egg(pokemon) then
    return jsonb_build_object('outcome', 'not_offered');
  end if;

  update public.coder_companions c set egg_received_at = now() where c.id = pokemon.id;
  if drawn is null then
    egg := public.roll_egg(caller, 'national');
    return jsonb_build_object('outcome', 'received', 'companion_id', egg);
  end if;

  gender := public.draw_gender(drawn);
  if gender = 'female' then
    select coalesce((select s.id from public.pokedex_species s
                      where s.form_of = drawn and s.slug like '%-female'), drawn)
      into drawn;
  end if;

  insert into public.coder_companions (user_id, species_id, egg_kind, is_shiny, gender, egg_from)
  values (caller, drawn, 'national', floor(random() * public.egg_shiny_odds(caller)) = 0, gender,
          pokemon.species_id)
  returning id into egg;
  return jsonb_build_object(
    'outcome', 'received',
    'companion_id', egg,
    'species', (select jsonb_build_object('species_id', s.id, 'ko_name', s.ko_name, 'en_name', s.en_name)
                  from public.pokedex_species s where s.id = receive_egg.species_id));
end;
$$;


-- ============================================================
-- box — as before, with the egg a Pokémon may give in place of a national
-- one, while it may give one.
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
               'ball', (select jsonb_build_object('id', i.id, 'ko_name', i.ko_name, 'en_name', i.en_name,
                                                  'sprite', i.sprite)
                          from public.pokedex_items i where i.id = c.ball),
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
               'needed_egg', case when c.level >= 50 and c.egg_received_at is null then (
                   select jsonb_build_object('species_id', s.id, 'ko_name', s.ko_name, 'en_name', s.en_name)
                     from public.pokedex_species s where s.id = public.needed_egg(c)) end,
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
revoke execute on function
  public.needed_egg(public.coder_companions),
  public.receive_egg(uuid, integer)
  from public;

grant execute on function public.receive_egg(uuid, integer) to authenticated;
