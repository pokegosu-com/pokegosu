-- ============================================================
-- retire_device — a machine retires itself.
--
-- Called by the retire-device Edge Function when `pokegosu auth logout` runs.
-- It is the same retirement the web does, asked for by the machine with its
-- own key instead of by the person with a session, so it is just as final:
-- the key stops working, the machine keeps the history it earned, and a login
-- afterwards is a new machine with an id of its own.
--
--   → {"outcome": "retired", "device_name": "laptop"}
--   → {"outcome": "unauthorized"}   an unknown key, or one already retired
--
-- A retired key is treated exactly like an unknown one, as ingest does: the
-- caller learns that the key does not work, not why.
-- ============================================================
create function public.retire_device(api_key_hash bytea)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  retired record;
begin
  -- The trigger stamps revoked_at with now() whatever is written here.
  update public.devices d
     set revoked_at = now()
   where d.api_key_hash = retire_device.api_key_hash
     and d.revoked_at is null
  returning d.name into retired;

  if retired is null then
    return jsonb_build_object('outcome', 'unauthorized');
  end if;
  return jsonb_build_object('outcome', 'retired', 'device_name', retired.name);
end;
$$;

revoke execute on function public.retire_device(bytea) from public;
grant execute on function public.retire_device(bytea) to service_role;
