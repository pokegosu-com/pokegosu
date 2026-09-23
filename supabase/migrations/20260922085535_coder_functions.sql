-- The functions behind coder: two the web calls as the signed-in person,
-- and two the Edge Functions call for a machine.
--
--   create_enrollment_code  web, as the person       security definer
--   usage                   web, as the person       runs as the caller
--   redeem_enrollment_code  Edge Function only       service_role
--   ingest                  Edge Function only       service_role
--
-- The last two assume the Edge Function has already checked their arguments
-- and do only the data work: what has to be atomic, or done in one round
-- trip. An expected outcome — a code that does not match, a key that is
-- revoked — comes back as a value, {"outcome": "..."}, so that the Edge
-- Function decides what it means in HTTP. The table constraints stay as the
-- last line of defence.
--
-- Postgres lets PUBLIC execute every new function, and anon and authenticated
-- are members of PUBLIC. So every function here has its execute revoked from
-- PUBLIC and granted back to exactly the role that calls it, at the end of
-- this file. A function added later needs the same; the tests check every
-- function in public, not just these.


-- ============================================================
-- create_enrollment_code — what a person carries to a machine.
--
--   {}  →  {"code": "XPTQ-4F2K", "expires_at": "..."}
--
-- A function rather than an insert because the person cannot be trusted to
-- pick their own code, and cannot see the table it goes into.
--
-- The alphabet drops the four characters people confuse — I, L, O and U —
-- which also keeps it from spelling anything. It is 32 characters and a byte
-- holds 256 values, so each byte modulo 32 is uniform. Eight characters is
-- about a trillion codes; a code also lives ten minutes and works once.
--
-- Only the sha256 of the eight characters, without the dash, is stored.
-- redeem-enrollment-code normalises what was typed back to that before
-- hashing it.
-- ============================================================
create function public.create_enrollment_code()
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  code text;
  expiry timestamptz := now() + interval '10 minutes';
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  -- Two unique constraints share the table: one row per account, and the code
  -- itself. Asking again replaces the account's own row, but a new code can
  -- still land on one somebody else holds; that is about one in a trillion,
  -- and drawing again costs nothing.
  for attempt in 1..3 loop
    select string_agg(
             substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ', get_byte(b, i) % 32 + 1, 1),
             '' order by i)
      into code
      from extensions.gen_random_bytes(8) as b, generate_series(0, 7) as i;

    begin
      -- The account's slot is reused rather than fought over: a plain insert
      -- would fail against a code asked for yesterday and never used, and
      -- nothing sweeps those, so that failure would be permanent. created_at
      -- moves too, or the row would claim to be older than it is.
      insert into public.enrollment_codes (code_hash, user_id, expires_at, created_at)
      values (sha256(convert_to(code, 'UTF8')), caller, expiry, now())
      on conflict on constraint enrollment_codes_user_id_key do update
        set code_hash  = excluded.code_hash,
            expires_at = excluded.expires_at,
            created_at = excluded.created_at;

      -- The only time the code exists anywhere but in the person's hands.
      return jsonb_build_object(
        'code', substr(code, 1, 4) || '-' || substr(code, 5),
        'expires_at', to_char(expiry at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
    exception when unique_violation then
      -- Collided with another account's code; draw again.
    end;
  end loop;

  raise exception 'enrollment code collided 3 times';
end;
$$;


-- ============================================================
-- usage — what the signed-in person has used over a range.
--
--   {"range_start": "2026-09-07T00:00:00Z", "range_end": "2026-09-14T00:00:00Z"}
--
--   → {"from": "...", "to": "...", "total": "123",
--      "devices": [{"device_id", "device_name", "tokens"}],
--      "hours":   [{"hour_bucket", "tokens"}]}
--
-- A function rather than a select because the screen wants sums, and the raw
-- rows of a long range would not fit in max_rows. It runs as its caller, so
-- RLS is what limits it to the caller's own rows.
--
-- The range comes from the caller because "today" and "this week" depend on
-- where the person is, and the server does not know that.
--
-- The grand total is a string. Every other figure is bounded by the range,
-- but a lifetime total is not, and JSON numbers stop being exact past 2^53.
-- ============================================================
create function public.usage(range_start timestamptz, range_end timestamptz)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
begin
  -- 22023 is invalid_parameter_value, which PostgREST answers with a 400.
  if range_start <> date_trunc('hour', range_start, 'UTC')
     or range_end <> date_trunc('hour', range_end, 'UTC') then
    raise exception 'range_start and range_end must be on the hour in UTC' using errcode = '22023';
  end if;
  if range_end <= range_start then
    raise exception 'range_end must be after range_start' using errcode = '22023';
  end if;
  -- A year of hourly buckets is already more than any screen wants, and the
  -- cap keeps one request from walking a whole account's history.
  if range_end - range_start > interval '400 days' then
    raise exception 'the range is longer than 400 days' using errcode = '22023';
  end if;

  return (
    with ledger as (
      select r.device_id, r.hour_bucket, r.tokens::bigint as tokens
        from public.usage_rollups r
       where r.hour_bucket >= range_start and r.hour_bucket < range_end
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
      'from', to_char(range_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'to', to_char(range_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
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
          from by_hour h), '[]'::jsonb))
  );
end;
$$;


-- ============================================================
-- redeem_enrollment_code — spend a code and register the machine with it.
--
-- The Edge Function normalises what was typed, hashes it, mints the machine's
-- key, and passes both hashes here. The plaintext key never reaches the database.
--
--   → {"outcome": "redeemed", "user_id": "..."}
--   → {"outcome": "code_invalid"}   expired, spent, or never issued
--   → {"outcome": "device_taken"}   that machine belongs to another account
--
-- A machine the same account already registered is enrolled again: someone
-- who deleted their settings and ran login once more should not be locked
-- out of their own laptop. It gets the new key and name, and loses its
-- revocation, since asking for a fresh code is adding it back. The old key
-- stops working the moment its hash is replaced. The machine keeps its id,
-- so its history stays with it.
--
-- One transaction: a machine that cannot be registered does not spend the
-- code, and the person can try again with it.
-- ============================================================
create function public.redeem_enrollment_code(
  code_hash bytea, device_id uuid, device_name text, api_key_hash bytea)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  owner uuid;
  registered uuid;
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

  insert into public.devices as d (id, user_id, name, api_key_hash)
  values (redeem_enrollment_code.device_id, owner,
          redeem_enrollment_code.device_name, redeem_enrollment_code.api_key_hash)
  on conflict (id) do update
    set name = excluded.name,
        api_key_hash = excluded.api_key_hash,
        revoked_at = null
    where d.user_id = excluded.user_id
  returning d.id into registered;

  -- Nothing came back: the id is taken, and not by this account. Raising
  -- sends it to the handler below with everything else that cannot register.
  if registered is null then
    raise sqlstate '23505';
  end if;

  return jsonb_build_object('outcome', 'redeemed', 'user_id', owner);
exception when unique_violation then
  -- Leaving through the handler rolls back the delete above, so the code
  -- survives. The machine id is the machine's own invention, so a clash with
  -- another account is a collision beyond reckoning or somebody trying it
  -- on; neither learns whose.
  return jsonb_build_object('outcome', 'device_taken');
end;
$$;


-- ============================================================
-- ingest — record what a machine has used.
--
-- The Edge Function has already checked the rows: each has a provider, an hour that is
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
create function public.ingest(api_key_hash bytea, rollups jsonb)
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
-- Who may call what.
-- ============================================================
revoke execute on function
  public.create_enrollment_code(),
  public.usage(timestamptz, timestamptz),
  public.redeem_enrollment_code(bytea, uuid, text, bytea),
  public.ingest(bytea, jsonb),
  public.enforce_device_retirement()
  from public;

grant execute on function public.create_enrollment_code() to authenticated;
grant execute on function public.usage(timestamptz, timestamptz) to authenticated;
grant execute on function public.redeem_enrollment_code(bytea, uuid, text, bytea) to service_role;
grant execute on function public.ingest(bytea, jsonb) to service_role;
