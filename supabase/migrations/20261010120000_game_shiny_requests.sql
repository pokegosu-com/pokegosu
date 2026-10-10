-- Now and then a request comes from a shiny Pokémon, as often as an egg
-- holds one. A shiny client's request is done in half a shift but pays a
-- whole one, so it is worth sending the best Pokémon to at once. Unlike the
-- family gift it is shown on the board: a shiny Pokémon is there to be seen.


-- ============================================================
-- coder_workplaces.is_shiny: whether the client is shiny, drawn with it.
-- Requests already up stay as they are.
-- ============================================================
alter table public.coder_workplaces
  add column is_shiny boolean not null default false;


-- ============================================================
-- Helpers. None is granted to anyone.
-- ============================================================

-- Whether a client drawn now is shiny: one time in shiny_odds, as an egg.
create function public.roll_shiny()
returns boolean
language sql
volatile
set search_path = ''
as $$
  select floor(random() * g.shiny_odds) = 0 from public.coder_settings g;
$$;

-- The active hours a shift lasts at a request: half of shift_hours, rounded
-- up, for a shiny client.
create function public.shift_length(is_shiny boolean)
returns smallint
language sql
stable
set search_path = ''
as $$
  select case when shift_length.is_shiny then ceil(g.shift_hours / 2.0)::smallint else g.shift_hours end
    from public.coder_settings g;
$$;

revoke execute on function public.roll_shiny(), public.shift_length(boolean) from public;


-- ============================================================
-- open_workplaces and replace_workplace — as before, with the client's
-- shininess drawn with it.
-- ============================================================
create or replace function public.open_workplaces(owner uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  n smallint;
  client integer;
begin
  for n in select generate_series(1, g.workplaces) from public.coder_settings g loop
    if not exists (select 1 from public.coder_workplaces w where w.user_id = owner and w.slot = n) then
      client := public.roll_client();
      insert into public.coder_workplaces (user_id, slot, client_id, task_id, is_shiny)
      values (owner, n, client, public.roll_task(client), public.roll_shiny());
    end if;
  end loop;
end;
$$;

create or replace function public.replace_workplace(workplace_id uuid)
returns void
language plpgsql
volatile
set search_path = ''
as $$
declare
  client integer := public.roll_client();
begin
  update public.coder_workplaces w
     set client_id = client, task_id = public.roll_task(client), is_shiny = public.roll_shiny(),
         emptied_at = now(), companion_id = null, assigned_at = null
   where w.id = replace_workplace.workplace_id;
end;
$$;


-- ============================================================
-- settle — as before, done after the request's own shift length, and the
-- next client drawn shiny or not.
-- ============================================================
create or replace function public.settle(workplace_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  place public.coder_workplaces;
  pokemon public.coder_companions;
  pay integer;
  gift integer := 0;
  line text;
  client integer;
begin
  perform public.lock_trainer(caller);
  select * into place from public.coder_workplaces w
   where w.id = settle.workplace_id and w.user_id = caller for update;
  if place.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if place.companion_id is null then
    return jsonb_build_object('outcome', 'empty');
  end if;
  if public.active_hours(caller, place.assigned_at) < public.shift_length(place.is_shiny) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  select * into pokemon from public.coder_companions c where c.id = place.companion_id;
  -- A whole shift's pay, however short the shift.
  select public.shift_pay(pokemon.species_id, pokemon.level, k.type1, k.type2) into pay
    from public.pokedex_species k where k.id = place.client_id;
  if pay > 0 then
    insert into public.coder_point_entries (user_id, points, reason) values (caller, pay, 'shift');
  end if;
  line := public.line_of(place.client_id, pokemon.species_id);
  if line is not null then
    select g.family_points into gift from public.coder_settings g;
    if gift > 0 then
      insert into public.coder_point_entries (user_id, points, reason) values (caller, gift, 'family');
    end if;
  end if;
  insert into public.coder_requests_done (user_id, companion_id, client_id)
  values (caller, pokemon.id, place.client_id);

  client := public.roll_client();
  update public.coder_workplaces w
     set client_id = client, task_id = public.roll_task(client), is_shiny = public.roll_shiny(),
         emptied_at = null, companion_id = null, assigned_at = null
   where w.id = place.id;
  return jsonb_build_object('outcome', 'settled', 'points', pay, 'family', gift, 'line', line);
end;
$$;


-- ============================================================
-- work — as before, with each request saying whether its client is shiny
-- and how long its shift is. Both stay hidden, with the client, until the
-- request arrives:
--
--   "workplaces": [{..., "is_shiny": true, "shift_hours": 4, ...}]
--
-- A worker's hours run up to its request's shift length.
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
