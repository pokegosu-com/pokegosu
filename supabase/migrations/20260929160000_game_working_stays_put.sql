-- A Pokémon out on a request is busy: nothing is done to it until its shift
-- is settled. It is not evolved, by level or by stone, gives no egg or
-- ribbon, and keeps its marks, so it comes back as the one that was sent.
-- set_main() and assign() already refuse it.
--
-- Each answers {"outcome": "working"} for it, as set_main() does.


-- ============================================================
-- at_work — whether a Pokémon is out on a request.
--
-- Not granted to anyone.
-- ============================================================
create function public.at_work(companion_id uuid)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (select 1 from public.coder_workplaces w where w.companion_id = at_work.companion_id);
$$;

revoke execute on function public.at_work(uuid) from public;


-- ============================================================
-- evolve — as before, but not at work.
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
  if public.at_work(pokemon.id) then
    return jsonb_build_object('outcome', 'working');
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
-- use_item — as before, but not at work.
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

  select e.id into next_form from public.item_evolutions(pokemon.species_id, pokemon.gender) e
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
-- receive_egg — as before, but not at work.
-- ============================================================
create or replace function public.receive_egg(companion_id uuid)
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

  update public.coder_companions c set egg_received_at = now() where c.id = pokemon.id;
  egg := public.roll_egg(caller, 'national');
  return jsonb_build_object('outcome', 'received', 'companion_id', egg);
end;
$$;


-- ============================================================
-- receive_ribbon — as before, but not at work.
-- ============================================================
create or replace function public.receive_ribbon(companion_id uuid, ribbon_id text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  pokemon public.coder_companions := public.lock_companion(auth.uid(), receive_ribbon.companion_id);
begin
  if pokemon.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if public.at_work(pokemon.id) then
    return jsonb_build_object('outcome', 'working');
  end if;
  if not exists (select 1 from public.coder_ribbons r where r.id = receive_ribbon.ribbon_id) then
    return jsonb_build_object('outcome', 'unknown_ribbon');
  end if;
  if exists (select 1 from public.coder_companion_ribbons cr
              where cr.companion_id = pokemon.id and cr.ribbon_id = receive_ribbon.ribbon_id) then
    return jsonb_build_object('outcome', 'already_received');
  end if;
  if not receive_ribbon.ribbon_id = any (public.eligible_ribbons(pokemon)) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  insert into public.coder_companion_ribbons (companion_id, ribbon_id)
  values (pokemon.id, receive_ribbon.ribbon_id);
  return jsonb_build_object('outcome', 'received');
end;
$$;


-- ============================================================
-- set_markings — as before, but not at work.
-- ============================================================
create or replace function public.set_markings(companion_id uuid, markings smallint)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  chosen public.coder_companions := public.lock_companion(auth.uid(), set_markings.companion_id);
begin
  if chosen.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if public.at_work(chosen.id) then
    return jsonb_build_object('outcome', 'working');
  end if;
  -- The table's check refuses a mark set to 3, with 23514.
  update public.coder_companions c set markings = set_markings.markings where c.id = chosen.id;
  return jsonb_build_object('outcome', 'set');
end;
$$;
