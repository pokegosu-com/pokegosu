-- ============================================================
-- work — as before, with the ribbons each Pokémon has received, so the
-- picker of who to send can mark those with the Helper Ribbon:
--
--   "pokemon": [{..., "ribbons": ["helper"], ...}]
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
               'is_shiny', case when up.arrived then w.is_shiny end,
               'shift_hours', case when up.arrived then len.hours end,
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
                   'hours', least(shift.hours, len.hours),
                   'aptitude', public.aptitude(c.species_id, k.type1, k.type2),
                   'points', public.shift_pay(c.species_id, c.level, k.type1, k.type2),
                   'can_settle', shift.hours >= len.hours) end)
             order by w.slot)
        from public.coder_workplaces w
        join public.pokedex_species k on k.id = w.client_id
        left join public.coder_companions c on c.id = w.companion_id
        cross join lateral (select public.active_hours(caller, w.emptied_at) as hours) waited
        cross join lateral (select public.request_arrived(caller, w.emptied_at) as arrived) up
        cross join lateral (select public.active_hours(caller, w.assigned_at) as hours) shift
        cross join lateral (select public.shift_length(w.is_shiny) as hours) len
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
               'ribbons', (select coalesce(jsonb_agg(cr.ribbon_id order by cr.ribbon_id), '[]'::jsonb)
                             from public.coder_companion_ribbons cr where cr.companion_id = c.id),
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
