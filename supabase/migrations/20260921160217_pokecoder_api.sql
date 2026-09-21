-- pokecoder's API: what the CLI and the web call, as PostgREST RPC.
--
--   POST /rest/v1/rpc/create_enrollment_code   the web, with a session
--   POST /rest/v1/rpc/redeem_enrollment_code   a machine, with nothing yet
--   POST /rest/v1/rpc/ingest                   a machine, with x-api-key
--   POST /rest/v1/rpc/usage                    the web, with a session
--
-- Every call also carries the project's publishable key as `apikey`, which is
-- what the gateway asks of anything under /rest/v1. It is not a secret, and
-- the CLI learns it from the web rather than from the person running it.
--
-- These live in their own schema, not in public, for two reasons. The schema
-- is the contract a released CLI depends on, so it holds nothing but that
-- contract; and nothing in public becomes callable by accident because it
-- happens to be a function.
--
-- Errors are raised with SQLSTATE PGRST, which PostgREST turns into exactly
-- the status and body given: {"code": "<ours>", "message": "...", ...}. The
-- code is what a client branches on; the message is for a person.

create schema api;
create schema private;

grant usage on schema api to anon, authenticated;



-- ============================================================
-- private helpers. Not exposed: PostgREST serves only the schemas listed in
-- config.toml, and private is not one of them.
-- ============================================================

-- fail raises an error PostgREST answers with the given status and code.
create function private.fail(status integer, code text, message text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise sqlstate 'PGRST' using
    message = json_build_object('code', code, 'message', message)::text,
    detail = json_build_object('status', status, 'headers', json_build_object())::text;
end;
$$;

-- usage runs as its caller so that RLS decides what it reads, which means its
-- caller has to be able to fail too.
grant usage on schema private to authenticated;
grant execute on function private.fail(integer, text, text) to authenticated;

-- new_enrollment_code draws eight characters from the system's random source.
--
-- The alphabet drops the four characters people confuse — I, L, O and U —
-- which also keeps it from spelling anything. It is 32 characters and a byte
-- holds 256 values, so taking each byte modulo 32 is uniform.
--
-- Eight characters over 32 is about a trillion codes. That is only half the
-- argument: a code lives ten minutes and works once.
create function private.new_enrollment_code()
returns text
language sql
volatile
set search_path = ''
as $$
  select string_agg(
           substr('0123456789ABCDEFGHJKMNPQRSTVWXYZ', get_byte(bytes, i) % 32 + 1, 1),
           '' order by i)
    from extensions.gen_random_bytes(8) as bytes,
         generate_series(0, 7) as i;
$$;

-- normalize_enrollment_code turns what a person typed into what was issued,
-- or into something that will simply not be found.
--
-- Nobody who reads a 1 as an I should be told their code is wrong, so the
-- dropped letters fold back to the digits they were mistaken for. Anything
-- else — spaces, the dash, a stray quote — is dropped. It does not judge the
-- input: a wrong length makes a string no digest matches, and "no such code"
-- is the honest answer to both a typo and a guess.
create function private.normalize_enrollment_code(typed text)
returns text
language sql
immutable
set search_path = ''
as $$
  select regexp_replace(translate(upper(typed), 'ILO', '110'), '[^0-9A-Z]', '', 'g');
$$;

-- digest is how both credentials are stored: sha256 of the text.
create function private.digest(value text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.sha256(convert_to(value, 'UTF8'));
$$;

-- hour_bucket parses a timestamp that is exactly on the hour in UTC.
--
-- The text is matched against RFC3339 before it is cast, because a cast alone
-- also accepts 'now', 'today' and 'infinity'. The schema checks the same
-- thing, but as a constraint violation that cannot say which row was wrong.
create function private.hour_bucket(value jsonb, field text)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
declare
  spelled text;
  at timestamptz;
begin
  if jsonb_typeof(value) is distinct from 'string' then
    perform private.fail(400, 'invalid_request', field || ' must be an RFC3339 timestamp');
  end if;

  spelled := value #>> '{}';
  if spelled !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$'
     or not pg_input_is_valid(spelled, 'timestamptz') then
    perform private.fail(400, 'invalid_request', field || ' is not a valid timestamp: ' || spelled);
  end if;

  at := spelled::timestamptz;
  if at <> date_trunc('hour', at, 'UTC') then
    perform private.fail(400, 'invalid_request', field || ' must be on the hour in UTC, got ' || spelled);
  end if;
  return at;
end;
$$;

-- utc spells an instant the way every part of this system does: RFC3339 in
-- UTC with no fractional seconds.
create function private.utc(at timestamptz)
returns text
language sql
immutable
set search_path = ''
as $$
  select to_char(at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
$$;

grant execute on function private.hour_bucket(jsonb, text) to authenticated;
grant execute on function private.utc(timestamptz) to authenticated;


-- ============================================================
-- create_enrollment_code — what a person carries to a machine.
--
--   {}  →  { "code": "XPTQ-4F2K", "expires_at": "..." }
--
-- Authenticated by the session, because this is where a machine's first
-- credential comes from and so it cannot require one.
-- ============================================================
create function api.create_enrollment_code()
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
    perform private.fail(401, 'unauthorized', 'sign in first: this needs a session, not an API key');
  end if;

  -- Two unique constraints share the table: one row per account, and the code
  -- itself. Asking again replaces the account's own row, but a new code can
  -- still land on one somebody else holds. That is about one in a trillion,
  -- and a retry costs nothing.
  for attempt in 1..3 loop
    code := private.new_enrollment_code();
    begin
      -- The account's slot is reused rather than fought over: a plain insert
      -- would fail against a code asked for yesterday and never used.
      insert into public.enrollment_codes (code_hash, user_id, expires_at, created_at)
      values (private.digest(code), caller, expiry, now())
      on conflict (user_id) do update
        set code_hash  = excluded.code_hash,
            expires_at = excluded.expires_at,
            created_at = excluded.created_at;

      -- The only time the code exists anywhere but in the caller's hands.
      return jsonb_build_object(
        'code', substr(code, 1, 4) || '-' || substr(code, 5),
        'expires_at', private.utc(expiry));
    exception when unique_violation then
      -- Collided with another account's code; draw again.
    end;
  end loop;

  raise exception 'enrollment code collided 3 times';
end;
$$;

grant execute on function api.create_enrollment_code() to authenticated;


-- ============================================================
-- redeem_enrollment_code — a machine trades a code for a credential.
--
--   { "code": "XPTQ-4F2K",
--     "device_id": "<uuid the machine made up>",
--     "device_name": "laptop" }
--
--   → { "api_key": "pkt_...", "device_id": "...", "device_name": "laptop" }
--
-- Nothing authenticates this call, because the code IS the credential and a
-- machine has nothing else yet. That is the whole reason the code is short
-- lived, single use, and one per account.
--
-- It is one transaction. If the machine cannot be registered, the code is
-- not spent either, and the person can try again with it.
-- ============================================================
create function api.redeem_enrollment_code(code text, device_id text, device_name text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  name text := regexp_replace(coalesce(device_name, ''), '^\s+|\s+$', '', 'g');
  id uuid;
  owner uuid;
  api_key text;
begin
  if coalesce(btrim(code), '') = '' then
    perform private.fail(400, 'invalid_request', 'code must not be blank');
  end if;
  if length(code) > 64 then
    perform private.fail(400, 'invalid_request', 'code must be at most 64 characters');
  end if;
  if device_id is null
     or device_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    perform private.fail(400, 'invalid_request', 'device_id must be a UUID');
  end if;
  if name = '' then
    perform private.fail(400, 'invalid_request', 'device_name must not be blank');
  end if;
  if length(name) > 100 then
    perform private.fail(400, 'invalid_request', 'device_name must be at most 100 characters');
  end if;
  id := lower(device_id)::uuid;

  -- One statement on purpose: only one delete can match a row, so two
  -- machines cannot both spend the same code. Expiry is the database's
  -- clock, so a machine with a wrong one changes nothing.
  delete from public.enrollment_codes
   where code_hash = private.digest(private.normalize_enrollment_code(code))
     and expires_at > now()
  returning user_id into owner;

  -- Expired, spent and never issued are one answer. Telling them apart
  -- would only help someone guessing.
  if owner is null then
    perform private.fail(401, 'enrollment_code_invalid', 'that code is not valid: ask the web for a new one');
  end if;

  -- The prefix makes a leaked key recognisable in logs and to secret
  -- scanners; the 32 random bytes are what make it a credential.
  api_key := 'pkt_' || encode(extensions.gen_random_bytes(32), 'hex');

  begin
    insert into public.devices (id, user_id, name, api_key_hash)
    values (id, owner, name, private.digest(api_key));
  exception when unique_violation then
    -- The machine already made itself known. Its id is its own invention, so
    -- this is a collision beyond reckoning or somebody trying it on, and
    -- neither gets to learn whose it is.
    perform private.fail(409, 'device_owned_by_another_account',
      'that machine is already registered to another account');
  end;

  -- The only time the plaintext exists anywhere but in the caller's hands.
  return jsonb_build_object('api_key', api_key, 'device_id', id, 'device_name', name);
end;
$$;

grant execute on function api.redeem_enrollment_code(text, text, text) to anon;


-- ============================================================
-- ingest — record what a machine has used.
--
--   x-api-key: pkt_...
--
--   { "rollups": [ { "provider": "claude_code",
--                    "hour_bucket": "2026-09-12T14:00:00Z",
--                    "tokens": 3200000 } ] }
--
--   → { "accepted": 1 }
--
-- The rows are absolute hourly totals, not increments, so sending the same
-- bucket again is harmless.
--
-- Which machine this is comes from the key, never from the body: a machine
-- cannot write a sibling's rows because it cannot name one.
--
-- Every check here duplicates a constraint the table already has. The
-- constraints are the last line of defence and cannot say which of ten
-- thousand rows is wrong; these can.
-- ============================================================
create function api.ingest(rollups jsonb)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  -- A routine sync carries one or two rows. The cap is for a first run
  -- backfilling months of logs; past it a client sends batches.
  max_rollups constant integer := 10000;

  api_key text := current_setting('request.headers', true)::json ->> 'x-api-key';
  machine record;
  entry jsonb;
  i integer;
  tokens numeric;
  providers text[] := '{}';
  hours timestamptz[] := '{}';
  counts bigint[] := '{}';
  repeat record;
  unknown text;
begin
  if coalesce(api_key, '') = '' then
    perform private.fail(401, 'unauthorized', 'x-api-key header is required');
  end if;

  -- A revoked key is treated exactly like an unknown one: the caller learns
  -- that the key does not work, not why.
  select d.id, d.user_id into machine
    from public.devices d
   where d.api_key_hash = private.digest(api_key)
     and d.revoked_at is null;
  if machine.id is null then
    perform private.fail(401, 'unauthorized', 'unknown or revoked API key');
  end if;

  if jsonb_typeof(rollups) is distinct from 'array' then
    perform private.fail(400, 'invalid_request', 'rollups must be an array');
  end if;
  if jsonb_array_length(rollups) = 0 then
    perform private.fail(400, 'invalid_request', 'rollups must not be empty');
  end if;
  if jsonb_array_length(rollups) > max_rollups then
    perform private.fail(400, 'invalid_request',
      format('rollups must hold at most %s entries; send them in batches', max_rollups));
  end if;

  for entry, i in select value, ordinality - 1 from jsonb_array_elements(rollups) with ordinality loop
    if jsonb_typeof(entry) <> 'object' then
      perform private.fail(400, 'invalid_request', format('rollups[%s] must be an object', i));
    end if;

    if jsonb_typeof(entry -> 'provider') is distinct from 'string'
       or btrim(entry ->> 'provider') = '' then
      perform private.fail(400, 'invalid_request', format('rollups[%s].provider must be a provider id', i));
    end if;

    -- Whole, non-negative, and small enough to have survived JSON: a client
    -- sending more than 2^53 has already lost precision before it arrives.
    if jsonb_typeof(entry -> 'tokens') is distinct from 'number' then
      perform private.fail(400, 'invalid_request', format('rollups[%s].tokens must be a whole number', i));
    end if;
    tokens := (entry ->> 'tokens')::numeric;
    if tokens <> trunc(tokens) or abs(tokens) > 9007199254740991 then
      perform private.fail(400, 'invalid_request', format('rollups[%s].tokens must be a whole number', i));
    end if;
    if tokens < 0 then
      perform private.fail(400, 'invalid_request', format('rollups[%s].tokens must not be negative', i));
    end if;

    providers := providers || btrim(entry ->> 'provider');
    hours := hours || private.hour_bucket(entry -> 'hour_bucket', format('rollups[%s].hour_bucket', i));
    counts := counts || tokens::bigint;
  end loop;

  -- One request cannot carry the same bucket twice: the upsert would have to
  -- pick a winner, and the client already knows which value it means.
  select r.n - 1 as i, r.provider, r.hour_bucket into repeat
    from (select p.provider, p.hour_bucket, p.n,
                 row_number() over (partition by p.provider, p.hour_bucket order by p.n) as seen
            from unnest(providers, hours) with ordinality as p(provider, hour_bucket, n)) r
   where r.seen > 1
   order by r.n
   limit 1;
  if repeat.i is not null then
    perform private.fail(400, 'invalid_request',
      format('rollups[%s] repeats %s at %s; send one row per bucket',
        repeat.i, repeat.provider, private.utc(repeat.hour_bucket)));
  end if;

  -- The foreign key would catch this too, but as a 500 naming a constraint.
  select p into unknown
    from unnest(providers) as p
   where not exists (select 1 from public.providers k where k.id = p)
   limit 1;
  if unknown is not null then
    perform private.fail(400, 'invalid_request',
      format('unknown provider "%s"; known providers are %s', unknown,
        (select string_agg(k.id, ', ' order by k.id) from public.providers k)));
  end if;

  insert into public.usage_rollups (user_id, device_id, provider, hour_bucket, tokens, updated_at)
  select machine.user_id, machine.id, r.provider, r.hour_bucket, r.tokens, now()
    from unnest(providers, hours, counts) as r(provider, hour_bucket, tokens)
  on conflict (user_id, device_id, provider, hour_bucket) do update
    set tokens = excluded.tokens,
        updated_at = excluded.updated_at;

  update public.devices set last_sync_at = now() where id = machine.id;

  return jsonb_build_object('accepted', cardinality(providers));
end;
$$;

grant execute on function api.ingest(jsonb) to anon;


-- ============================================================
-- usage — what an account has used, for the web.
--
--   { "range_start": "2026-09-07T00:00:00Z",
--     "range_end":   "2026-09-14T00:00:00Z" }
--
--   → { "from": "...", "to": "...", "total": "123",
--       "devices": [ { "device_id", "device_name", "tokens" } ],
--       "hours":   [ { "hour_bucket", "tokens" } ] }
--
-- The range comes from the caller because "today" and "this week" depend on
-- where the person is, and the server does not know that.
--
-- It runs as the caller, so RLS is what limits it to their own rows. It
-- aggregates in SQL so that no screen has to page through max_rows.
--
-- The grand total is a string. Every other figure is bounded by the range,
-- but a lifetime total is not, and JSON numbers stop being exact past 2^53.
-- ============================================================
create function api.usage(range_start jsonb, range_end jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  -- A year of hourly buckets is already more than any screen wants, and the
  -- cap keeps one request from walking a whole account's history.
  max_days constant integer := 400;
  since timestamptz := private.hour_bucket(range_start, 'range_start');
  until timestamptz := private.hour_bucket(range_end, 'range_end');
  days numeric;
begin
  if until <= since then
    perform private.fail(400, 'invalid_request', 'range_end must be after range_start');
  end if;
  days := extract(epoch from until - since) / 86400;
  if days > max_days then
    perform private.fail(400, 'invalid_request',
      format('the range covers %s days; ask for at most %s', round(days), max_days));
  end if;

  return (
    with ledger as (
      select r.device_id, r.hour_bucket, r.tokens::bigint as tokens
        from public.usage_rollups r
       where r.hour_bucket >= since and r.hour_bucket < until
    ),
    by_device as (
      select ledger.device_id, d.name, sum(ledger.tokens) as tokens
        from ledger
        left join public.devices d on d.id = ledger.device_id
       group by ledger.device_id, d.name
    ),
    by_hour as (
      select ledger.hour_bucket, sum(ledger.tokens) as tokens
        from ledger
       group by ledger.hour_bucket
    )
    select jsonb_build_object(
      'from', private.utc(since),
      'to', private.utc(until),
      'total', coalesce((select sum(tokens) from ledger), 0)::text,
      'devices', coalesce((
        select jsonb_agg(
                 jsonb_build_object('device_id', device_id, 'device_name', name, 'tokens', tokens)
                 order by tokens desc, device_id::text)
          from by_device), '[]'::jsonb),
      'hours', coalesce((
        select jsonb_agg(
                 jsonb_build_object('hour_bucket', private.utc(hour_bucket), 'tokens', tokens)
                 order by hour_bucket)
          from by_hour), '[]'::jsonb))
  );
end;
$$;

grant execute on function api.usage(jsonb, jsonb) to authenticated;


-- ============================================================
-- Postgres lets PUBLIC execute every new function, and anon and authenticated
-- are members of PUBLIC. Taking that away is what makes each grant above the
-- whole list of who may call what.
--
-- It has to be a revoke after the fact. `alter default privileges in schema`
-- cannot remove the global default, only add to it, so any function added to
-- these schemas later needs the same revoke in its own migration.
-- ============================================================
revoke execute on all functions in schema api, private from public;
