-- The data side of the pokecoder API.
--
-- The API app (a Worker) owns everything about a request: rate limits, who is
-- calling, whether the body is well formed, and what each answer means in
-- HTTP. It generates and hashes codes and keys, too. What it cannot do in one
-- round trip, or atomically, it hands to a function here, called through
-- PostgREST with the secret key.
--
-- So these functions assume their arguments are already checked and do only
-- the data work. The table constraints stay as the last line of defence.
--
-- An expected outcome — a code that does not match, a key that is revoked —
-- comes back as a value, {"outcome": "..."}, not as an error, so that the app
-- decides what it means. Errors are for what nobody expected.
--
-- Only service_role may execute anything here. The schema has to be exposed
-- to PostgREST for the app to reach it, which makes that grant the whole of
-- the protection.

create schema pokecoder;

grant usage on schema pokecoder to service_role;


-- ============================================================
-- create_enrollment_code — store the code a person will carry to a machine.
--
-- The app draws the code, shows it once, and passes its sha256 here.
--
--   → {"outcome": "created"}
--   → {"outcome": "collision"}  the code is another account's; draw again
-- ============================================================
create function pokecoder.create_enrollment_code(user_id uuid, code_hash bytea, expires_at timestamptz)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  -- The account's slot is reused rather than fought over: a plain insert
  -- would fail against a code asked for yesterday and never used, and nothing
  -- sweeps those, so that failure would be permanent. created_at moves too,
  -- or the row would claim to be older than it is.
  insert into public.enrollment_codes (code_hash, user_id, expires_at, created_at)
  values (create_enrollment_code.code_hash, create_enrollment_code.user_id,
          create_enrollment_code.expires_at, now())
  on conflict on constraint enrollment_codes_user_id_key do update
    set code_hash  = excluded.code_hash,
        expires_at = excluded.expires_at,
        created_at = excluded.created_at;

  return jsonb_build_object('outcome', 'created');
exception when unique_violation then
  -- Two unique constraints share the table. The one above is handled; this is
  -- the other, the code itself, about one in a trillion.
  return jsonb_build_object('outcome', 'collision');
end;
$$;


-- ============================================================
-- redeem_enrollment_code — spend a code and register the machine with it.
--
-- The app normalises what was typed, hashes it, mints the machine's key, and
-- passes both hashes here. The plaintext key never reaches the database.
--
--   → {"outcome": "redeemed", "user_id": "..."}
--   → {"outcome": "code_invalid"}   expired, spent, or never issued
--   → {"outcome": "device_taken"}   that machine id is already registered
--
-- One transaction: a machine that cannot be registered does not spend the
-- code, and the person can try again with it.
-- ============================================================
create function pokecoder.redeem_enrollment_code(
  code_hash bytea, device_id uuid, device_name text, api_key_hash bytea)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  owner uuid;
begin
  -- One statement on purpose: only one delete can match a row, so two
  -- machines cannot both spend the same code. Expiry is the database's clock,
  -- so a machine with a wrong one changes nothing.
  delete from public.enrollment_codes e
   where e.code_hash = redeem_enrollment_code.code_hash
     and e.expires_at > now()
  returning e.user_id into owner;

  -- Expired, spent and never issued are one answer. Telling them apart would
  -- only help someone guessing.
  if owner is null then
    return jsonb_build_object('outcome', 'code_invalid');
  end if;

  insert into public.devices (id, user_id, name, api_key_hash)
  values (redeem_enrollment_code.device_id, owner,
          redeem_enrollment_code.device_name, redeem_enrollment_code.api_key_hash);

  return jsonb_build_object('outcome', 'redeemed', 'user_id', owner);
exception when unique_violation then
  -- Leaving through the handler rolls back the delete above, so the code
  -- survives. The machine id is the machine's own invention, so a clash is a
  -- collision beyond reckoning or somebody trying it on; neither learns whose.
  return jsonb_build_object('outcome', 'device_taken');
end;
$$;


-- ============================================================
-- ingest — record what a machine has used.
--
-- The app has already checked the rows: each has a provider, an hour that is
-- on the hour in UTC, a whole non-negative count, and no bucket appears twice.
--
--   rollups: [{"provider": "claude_code",
--              "hour_bucket": "2026-09-12T14:00:00Z",
--              "tokens": 3200000}]
--
--   → {"outcome": "accepted", "accepted": 1}
--   → {"outcome": "unauthorized"}    unknown or revoked key
--   → {"outcome": "unknown_provider", "provider": "...", "known": [...]}
--
-- The key is looked up here rather than in a call of its own, so a sync costs
-- one round trip. Which machine this is comes from the key and never from the
-- rows: a machine cannot write a sibling's rows because it cannot name one.
--
-- The rows are absolute hourly totals, so sending a bucket again replaces it.
-- ============================================================
create function pokecoder.ingest(api_key_hash bytea, rollups jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  machine record;
  unknown text;
  accepted integer;
begin
  -- A revoked key is treated exactly like an unknown one.
  select d.id, d.user_id into machine
    from public.devices d
   where d.api_key_hash = ingest.api_key_hash
     and d.revoked_at is null;
  if machine.id is null then
    return jsonb_build_object('outcome', 'unauthorized');
  end if;

  -- The foreign key would catch this too, but as an error naming a
  -- constraint, and the client could not tell which provider to fix.
  select r.provider into unknown
    from jsonb_to_recordset(rollups) as r(provider text)
   where not exists (select 1 from public.providers p where p.id = r.provider)
   limit 1;
  if unknown is not null then
    return jsonb_build_object(
      'outcome', 'unknown_provider',
      'provider', unknown,
      'known', (select jsonb_agg(p.id order by p.id) from public.providers p));
  end if;

  insert into public.usage_rollups (user_id, device_id, provider, hour_bucket, tokens, updated_at)
  select machine.user_id, machine.id, r.provider, r.hour_bucket, r.tokens, now()
    from jsonb_to_recordset(rollups) as r(provider text, hour_bucket timestamptz, tokens bigint)
  on conflict (user_id, device_id, provider, hour_bucket) do update
    set tokens = excluded.tokens,
        updated_at = excluded.updated_at;
  get diagnostics accepted = row_count;

  update public.devices set last_sync_at = now() where id = machine.id;

  return jsonb_build_object('outcome', 'accepted', 'accepted', accepted);
end;
$$;


-- ============================================================
-- usage — what an account has used over a range, for the web.
--
-- The app has already checked the range: both ends on the hour, the end after
-- the start, and no longer than it allows.
--
--   → {"from": "...", "to": "...", "total": "123",
--      "devices": [{"device_id", "device_name", "tokens"}],
--      "hours":   [{"hour_bucket", "tokens"}]}
--
-- It aggregates here so that nothing pages through max_rows.
--
-- The grand total is a string. Every other figure is bounded by the range,
-- but a lifetime total is not, and JSON numbers stop being exact past 2^53.
-- ============================================================
create function pokecoder.usage(user_id uuid, range_start timestamptz, range_end timestamptz)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  with ledger as (
    select r.device_id, r.hour_bucket, r.tokens::bigint as tokens
      from public.usage_rollups r
     where r.user_id = usage.user_id
       and r.hour_bucket >= usage.range_start
       and r.hour_bucket < usage.range_end
  ),
  by_device as (
    select l.device_id, d.name, sum(l.tokens) as tokens
      from ledger l
      left join public.devices d on d.id = l.device_id
     group by l.device_id, d.name
  ),
  by_hour as (
    select l.hour_bucket, sum(l.tokens) as tokens
      from ledger l
     group by l.hour_bucket
  )
  select jsonb_build_object(
    'from', to_char(usage.range_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'to', to_char(usage.range_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'total', coalesce((select sum(l.tokens) from ledger l), 0)::text,
    'devices', coalesce((
      select jsonb_agg(
               jsonb_build_object('device_id', b.device_id, 'device_name', b.name, 'tokens', b.tokens)
               order by b.tokens desc, b.device_id::text)
        from by_device b), '[]'::jsonb),
    'hours', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'hour_bucket', to_char(h.hour_bucket at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                 'tokens', h.tokens)
               order by h.hour_bucket)
        from by_hour h), '[]'::jsonb));
$$;


-- ============================================================
-- Who may call what.
--
-- Postgres lets PUBLIC execute every new function, and anon and authenticated
-- are members of PUBLIC. `alter default privileges in schema` cannot take the
-- global default away, only add to it, so it is revoked after the fact — and
-- a function added to this schema later needs the same revoke in its own
-- migration. The test suite checks every function here, not just these.
-- ============================================================
revoke execute on all functions in schema pokecoder from public;
grant execute on all functions in schema pokecoder to service_role;
