-- A request settled is followed by the next at once; only one turned down
-- waits a shift's length of active hours. Waiting after work done only held
-- a person back, while the wait after a reroll is what keeps them from
-- rerolling until a request suits the Pokémon they have.


-- ============================================================
-- settle — as before, but the next request is up at once, as the first is:
-- emptied_at stays null.
--
--   → {"outcome": "settled", "points": 172}
--   → {"outcome": "not_ready"} | {"outcome": "empty"} | {"outcome": "not_found"}
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
  if public.active_hours(caller, place.assigned_at) < (select g.shift_hours from public.coder_settings g) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  select * into pokemon from public.coder_companions c where c.id = place.companion_id;
  select public.shift_pay(pokemon.species_id, pokemon.level, k.type1, k.type2) into pay
    from public.pokedex_species k where k.id = place.client_id;
  if pay > 0 then
    insert into public.coder_point_entries (user_id, points, reason) values (caller, pay, 'shift');
  end if;

  client := public.roll_client();
  update public.coder_workplaces w
     set client_id = client, task_id = public.roll_task(client), emptied_at = null,
         companion_id = null, assigned_at = null
   where w.id = place.id;
  return jsonb_build_object('outcome', 'settled', 'points', pay);
end;
$$;
