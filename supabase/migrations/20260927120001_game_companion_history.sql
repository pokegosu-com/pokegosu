-- ============================================================
-- companion_history — where a companion came from, and when it was the
-- partner.
--
--   {"companion_id": "..."}
--
--   → {"outcome": "found",
--      "egg_kind": {"id", "ko_name", "en_name"},
--      "created_at": "...", "hatched_at": "..." | null,
--      "main_periods": [{"started_at", "ended_at" | null}]}
--   → {"outcome": "not_found"}
--
-- A Pokémon's page in the box says which egg it hatched from and the times it
-- was the partner, oldest first; a period still open has no ended_at. That is
-- the first thing to read coder_main_periods, which stays ungranted: this
-- hands out the caller's own rows and nothing else, and a companion that is
-- not theirs is not_found, as the other buttons answer.
--
-- Mains from before 20260926120004 were opened when that migration ran, so a
-- long-standing partner's first period starts then, not when it was chosen.
-- ============================================================
create function public.companion_history(companion_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  found_one public.coder_companions;
begin
  select c.* into found_one
    from public.coder_companions c
   where c.id = companion_history.companion_id and c.user_id = caller;
  if found_one.id is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  return jsonb_build_object(
    'outcome', 'found',
    'egg_kind', (select jsonb_build_object('id', k.id, 'ko_name', k.ko_name, 'en_name', k.en_name)
                   from public.coder_egg_kinds k where k.id = found_one.egg_kind),
    'created_at', found_one.created_at,
    'hatched_at', found_one.hatched_at,
    'main_periods', coalesce((
      select jsonb_agg(jsonb_build_object('started_at', p.started_at, 'ended_at', p.ended_at)
                       order by p.started_at, p.id)
        from public.coder_main_periods p
       where p.companion_id = found_one.id and p.user_id = caller), '[]'::jsonb));
end;
$$;

revoke execute on function public.companion_history(uuid) from public;
grant execute on function public.companion_history(uuid) to authenticated;
