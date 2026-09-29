-- The partner stays home: it is the one tokens raise, so it takes no request.
-- A Pokémon out on a request cannot become the partner until it is back,
-- or the one rule would undo the other. A partner already out when this
-- came in finishes its shift as usual.


-- ============================================================
-- work — as before, with each Pokémon saying whether it is the partner:
--
--   "pokemon": [{..., "level", "is_main", "types", ...}]
--
-- The partner stays in the list, so a partner already out can be shown at
-- its workplace; the screen leaves it out of who may go.
-- ============================================================
create or replace function public.work()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  trainer public.coder_trainers;
  g public.coder_settings;
  hours integer;
  unpaid integer;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  select * into trainer from public.coder_trainers t where t.user_id = caller;
  if not found then
    return jsonb_build_object('started', false);
  end if;
  select * into g from public.coder_settings;

  hours := public.active_hours(caller, trainer.work_started_at);
  unpaid := greatest(0, hours - trainer.work_hours_paid);

  return jsonb_build_object(
    'started', true,
    'points', public.point_balance(caller),
    'rules', jsonb_build_object(
      'points_per_hour', g.points_per_hour,
      'shift_hours', g.shift_hours,
      'min_work_level', g.min_work_level,
      'bonus_every_hours', g.bonus_every_hours,
      'bonus_points', g.bonus_points),
    'trainer', jsonb_build_object(
      'name', (select p.display_name from public.profiles p where p.id = caller),
      'hours', hours,
      'hours_paid', trainer.work_hours_paid,
      'points_waiting', unpaid * g.points_per_hour
        + (hours / g.bonus_every_hours - trainer.work_hours_paid / g.bonus_every_hours) * g.bonus_points,
      'hours_to_bonus', g.bonus_every_hours - hours % g.bonus_every_hours),
    'workplaces', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', w.id,
               'slot', w.slot,
               'arrived', up.arrived,
               'hours_to_arrive', case when up.arrived then 0 else g.shift_hours - waited.hours end,
               'client', case when up.arrived then
                   jsonb_build_object('species_id', k.id, 'ko_name', k.ko_name, 'en_name', k.en_name,
                                      'sprites', k.sprites) end,
               'task', case when up.arrived then
                   (select jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                      from public.coder_request_tasks t where t.id = w.task_id) end,
               'types', case when up.arrived then
                   (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                     order by t.id = k.type2)
                      from public.pokedex_types t where t.id in (k.type1, k.type2)) end,
               'can_reroll', up.arrived and w.companion_id is null,
               'worker', case when w.companion_id is not null then jsonb_build_object(
                   'companion_id', w.companion_id,
                   'hours', least(shift.hours, g.shift_hours),
                   'aptitude', public.aptitude(c.species_id, k.type1, k.type2),
                   'points', public.shift_pay(c.species_id, c.level, k.type1, k.type2),
                   'can_settle', shift.hours >= g.shift_hours) end)
             order by w.slot)
        from public.coder_workplaces w
        join public.pokedex_species k on k.id = w.client_id
        left join public.coder_companions c on c.id = w.companion_id
        cross join lateral (select public.active_hours(caller, w.emptied_at) as hours) waited
        cross join lateral (select public.request_arrived(caller, w.emptied_at) as arrived) up
        cross join lateral (select public.active_hours(caller, w.assigned_at) as hours) shift
       where w.user_id = caller), '[]'::jsonb),
    'pokemon', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', c.id,
               'species_id', p.id,
               'ko_name', p.ko_name,
               'en_name', p.en_name,
               'sprites', p.sprites,
               'is_shiny', c.is_shiny,
               'gender', c.gender,
               'level', c.level,
               'is_main', c.id = trainer.main_companion_id,
               'types', (select jsonb_agg(jsonb_build_object('id', t.id, 'ko_name', t.ko_name, 'en_name', t.en_name)
                                          order by t.id = p.type2)
                           from public.pokedex_types t where t.id in (p.type1, p.type2)),
               'workplace_id', (select w.id from public.coder_workplaces w where w.companion_id = c.id),
               'offers', (select jsonb_agg(jsonb_build_object(
                                   'workplace_id', w.id,
                                   'aptitude', public.aptitude(p.id, k.type1, k.type2),
                                   'points', public.shift_pay(p.id, c.level, k.type1, k.type2))
                                 order by w.slot)
                            from public.coder_workplaces w
                            join public.pokedex_species k on k.id = w.client_id
                           where w.user_id = caller and public.request_arrived(caller, w.emptied_at)))
             order by c.level desc, c.hatched_at)
        from public.coder_companions c
        join public.pokedex_species p on p.id = c.species_id
       where c.user_id = caller and c.hatched_at is not null and c.level >= g.min_work_level), '[]'::jsonb));
end;
$$;


-- ============================================================
-- assign — as before, but not the partner.
--
--   → {"outcome": "partner"}     it is the partner
-- ============================================================
create or replace function public.assign(workplace_id uuid, companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  pokemon public.coder_companions := public.lock_companion(caller, assign.companion_id);
  place public.coder_workplaces;
begin
  select * into place from public.coder_workplaces w
   where w.id = assign.workplace_id and w.user_id = caller for update;
  if pokemon.id is null or place.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if not public.request_arrived(caller, place.emptied_at) then
    return jsonb_build_object('outcome', 'not_arrived');
  end if;
  if place.companion_id is not null then
    return jsonb_build_object('outcome', 'occupied');
  end if;
  if exists (select 1 from public.coder_workplaces w where w.companion_id = pokemon.id) then
    return jsonb_build_object('outcome', 'working');
  end if;
  if exists (select 1 from public.coder_trainers t
              where t.user_id = caller and t.main_companion_id = pokemon.id) then
    return jsonb_build_object('outcome', 'partner');
  end if;
  if pokemon.level is null or pokemon.level < (select g.min_work_level from public.coder_settings g) then
    return jsonb_build_object('outcome', 'too_low');
  end if;

  update public.coder_workplaces w set companion_id = pokemon.id, assigned_at = now()
   where w.id = place.id;
  return jsonb_build_object('outcome', 'assigned');
end;
$$;


-- ============================================================
-- set_main — as before, but not a Pokémon out on a request.
--
--   → {"outcome": "working"}     it is at a workplace
-- ============================================================
create or replace function public.set_main(companion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  chosen public.coder_companions := public.lock_companion(caller, set_main.companion_id);
begin
  if chosen.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if exists (select 1 from public.coder_workplaces w where w.companion_id = chosen.id) then
    return jsonb_build_object('outcome', 'working');
  end if;
  update public.coder_trainers t set main_companion_id = chosen.id where t.user_id = caller;
  return jsonb_build_object('outcome', 'set');
end;
$$;
