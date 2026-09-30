-- ============================================================
-- whoami — a machine asks which machine it is, and whose.
--
-- Called by the whoami Edge Function for `pokegosu auth status`, with the
-- digest of the key the machine holds. The settings on the machine say what
-- it was enrolled as; only this says whether that still holds, and the name
-- of the account, which a person can change at any time.
--
--   → {"outcome": "found", "device_id": "...", "device_name": "laptop",
--      "display_name": "Ash"}
--   → {"outcome": "unauthorized"}   unknown or retired key
--
-- display_name is null for an account that has not picked a handle yet.
-- ============================================================
create function public.whoami(api_key_hash bytea)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  -- A revoked key is treated exactly like an unknown one, as ingest does.
  select coalesce(
    (select jsonb_build_object(
              'outcome', 'found',
              'device_id', d.id,
              'device_name', d.name,
              'display_name', p.display_name)
       from public.devices d
       left join public.profiles p on p.id = d.user_id
      where d.api_key_hash = whoami.api_key_hash
        and d.revoked_at is null),
    jsonb_build_object('outcome', 'unauthorized'));
$$;

revoke execute on function public.whoami(bytea) from public;
grant execute on function public.whoami(bytea) to service_role;
