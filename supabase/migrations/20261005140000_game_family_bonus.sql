-- A Pokémon of the client's own line, as the pokedex draws it, gets a gift
-- from the client on top of the pay: Raichu's request done by Pichu, Pikachu
-- or Raichu. It is a flat amount rather than a multiplier, because a line
-- mostly shares its types and so works for itself at half aptitude. work()
-- does not show it beforehand: it is meant to be found, not planned for.


-- ============================================================
-- coder_settings.family_points: the gift. 320 is what a Lv.50 Pokémon earns
-- for a shift at four times aptitude.
-- ============================================================
alter table public.coder_settings
  add column family_points integer not null default 320 check (family_points >= 0);
alter table public.coder_settings
  alter column family_points drop default;

alter table public.coder_point_entries
  drop constraint coder_point_entries_reason_check,
  add constraint coder_point_entries_reason_check
    check (reason in ('shift', 'trainer', 'bonus', 'purchase', 'family'));


-- ============================================================
-- line_of — where a form stands on another's line, as the line's page in the
-- pokedex draws it: the way down to it and all that comes after. 'before' is
-- an earlier stage, 'after' a later one, 'same' the form itself, and null off
-- the line. Eevee's line holds all eight of its evolutions; Vaporeon's holds
-- only Eevee. Raichu's holds Pichu, Pikachu and its Megas, but not Alolan
-- Raichu.
-- ============================================================
create function public.line_of(client_id integer, species_id integer)
returns text
language sql
stable
set search_path = ''
as $$
  with recursive
    up as (
      select s.id, s.evolves_from_id from public.pokedex_species s where s.id = line_of.client_id
      union all
      select s.id, s.evolves_from_id from public.pokedex_species s join up on s.id = up.evolves_from_id
    ),
    down as (
      select s.id from public.pokedex_species s where s.id = line_of.client_id
      union all
      select s.id from public.pokedex_species s join down on s.evolves_from_id = down.id
    )
  select case
    when line_of.species_id = line_of.client_id then 'same'
    when line_of.species_id in (select id from up) then 'before'
    when line_of.species_id in (select id from down) then 'after'
  end;
$$;


-- ============================================================
-- settle — as before, with the client's gift where the Pokémon is of its line.
--
-- "line" says where the Pokémon stands on the client's line, for how the
-- client gives: to an earlier stage as to a child, to a later one as to one
-- it looks up to.
--
--   → {"outcome": "settled", "points": 172, "family": 0 | 320, "line": null | "before" | "after" | "same"}
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
  if public.active_hours(caller, place.assigned_at) < (select g.shift_hours from public.coder_settings g) then
    return jsonb_build_object('outcome', 'not_ready');
  end if;

  select * into pokemon from public.coder_companions c where c.id = place.companion_id;
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
     set client_id = client, task_id = public.roll_task(client), emptied_at = null,
         companion_id = null, assigned_at = null
   where w.id = place.id;
  return jsonb_build_object('outcome', 'settled', 'points', pay, 'family', gift, 'line', line);
end;
$$;

revoke execute on function public.line_of(integer, integer) from public;
