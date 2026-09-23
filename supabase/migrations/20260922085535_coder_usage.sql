-- coder: how many tokens a coding agent spent, by the hour.
--
-- A machine uploads absolute hourly totals through the ingest Edge Function,
-- and the web reads them back summed over a range. Which machine a row
-- belongs to comes from the account's device table, in the migration before
-- this one: enrolling is the account's business, not coder's.

create domain public.token_count as bigint check (value >= 0);


-- ============================================================
-- providers: supported coding agents (reference data)
-- ============================================================
create table public.providers (
  id           text primary key,
  display_name text not null
);

insert into public.providers (id, display_name) values
  ('claude_code', 'Claude Code');



-- ============================================================
-- usage_rollups: the ledger. Hourly absolute values, updated by upsert.
-- The composite primary key is the conflict target, which makes
-- re-uploading the same data idempotent.
--
-- The hour_bucket check is a last line of defence: each client implements
-- its own parser, and a truncation bug would otherwise create several
-- rows for the same hour without violating the PK.
--
-- infinity is checked separately because it slips past the first rule: it
-- truncates to itself, so it is "on the hour" by that measure. A row like
-- that would hide from every range a screen asks for while still counting
-- toward the lifetime total the game spends.
--
-- It names UTC rather than letting date_trunc use the session's timezone.
-- Whole-hour offsets truncate identically, but a zone offset by part of
-- an hour does not: with timezone = 'Asia/Kolkata' (+05:30) the two
-- argument form rejects 16:00Z, which is a correct value. That would bite
-- hardest on a restore, where COPY re-checks every constraint in whatever
-- session happens to be running it.
-- ============================================================
create table public.usage_rollups (
  user_id     uuid not null references auth.users on delete cascade,
  device_id   uuid not null,
  provider    text not null references public.providers (id),
  hour_bucket timestamptz not null
                constraint hour_bucket_is_truncated
                check (hour_bucket = date_trunc('hour', hour_bucket, 'UTC'))
                constraint hour_bucket_is_a_real_instant
                check (isfinite(hour_bucket)),
  tokens      public.token_count not null,
  updated_at  timestamptz not null default now(),
  primary key (user_id, device_id, provider, hour_bucket),

  -- The machine and the owner are checked together, so a row cannot claim
  -- one account's name over another account's machine.
  --
  -- restrict, not cascade: a machine is retired by setting revoked_at, not
  -- by deleting the row. Deleting it would take its history with it, and
  -- the history is not the machine's — it is the account's. Since a
  -- companion's progress is earned minus invested, and invested does not
  -- go down, dropping a retired laptop's tokens leaves the balance
  -- permanently short by everything that laptop ever did.
  --
  -- Closing an account still works: the rollups go first, by their own
  -- reference to auth.users, so there is nothing left to restrict.
  foreign key (device_id, user_id) references public.devices (id, user_id)
    on delete restrict
);

create index on public.usage_rollups (user_id, hour_bucket desc);



-- ============================================================
-- Access. As with devices: everything away first, then only what the web
-- needs. Rollups are read through usage() below, which runs as its caller.
-- ============================================================
revoke all on public.providers, public.usage_rollups from anon, authenticated;

alter table public.providers     enable row level security;
alter table public.usage_rollups enable row level security;

-- Providers are reference data: their display names are for any screen.
grant select on public.providers to authenticated;

create policy "anyone signed in can read providers"
  on public.providers for select
  to authenticated
  using (true);

grant select on public.usage_rollups to authenticated;

create policy "owners can read their rollups"
  on public.usage_rollups for select
  to authenticated
  using ((select auth.uid()) = user_id);


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
  -- A month of hourly buckets is 720 rows per machine, which is what a screen
  -- of hours can show. A longer view wants its hours summed into days first,
  -- and that is a different function rather than a longer range of this one.
  if range_end - range_start > interval '30 days' then
    raise exception 'the range is longer than 30 days' using errcode = '22023';
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
-- ingest — record what a machine has used.
--
-- The Edge Function has already checked the rows: each has a provider, an hour that is
-- on the hour in UTC, a whole non-negative count, and no bucket appears twice.
--
--   rollups: [{"provider": "claude_code",
--              "hour_bucket": "2026-09-12T14:00:00Z",
--              "tokens": 3200000}]
--
--   → {"outcome": "accepted", "accepted": 1, "ignored": 0}
--   → {"outcome": "unauthorized"}    unknown or revoked key
--   → {"outcome": "unknown_provider", "provider": "...", "known": [...]}
--
-- The key is looked up here rather than in a call of its own, so a sync costs
-- one round trip. Which machine this is comes from the key and never from the
-- rows: a machine cannot write a sibling's rows because it cannot name one.
--
-- The rows are absolute hourly totals, so sending a bucket again replaces it.
--
-- Hours from before the machine was enrolled are ignored rather than refused.
-- An agent that has been running for months leaves months of logs, and none
-- of it is the account's: the account learned of this machine when it let it
-- in. Ignoring rather than refusing keeps a client that sends them from
-- failing over something it cannot fix, and keeps the rule the server's
-- rather than every client's. The hour the enrolment fell in counts whole.
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
  select d.id, d.user_id, date_trunc('hour', d.created_at, 'UTC') as enrolled_hour
    into machine
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
   where r.hour_bucket >= machine.enrolled_hour
  on conflict (user_id, device_id, provider, hour_bucket) do update
    set tokens = excluded.tokens,
        updated_at = excluded.updated_at;
  get diagnostics accepted = row_count;

  update public.devices set last_sync_at = now() where id = machine.id;

  return jsonb_build_object(
    'outcome', 'accepted',
    'accepted', accepted,
    'ignored', jsonb_array_length(rollups) - accepted);
end;
$$;



-- ============================================================
-- Who may call what. See the note in the migration before this one.
-- ============================================================
revoke execute on function
  public.usage(timestamptz, timestamptz),
  public.ingest(bytea, jsonb)
  from public;

grant execute on function public.usage(timestamptz, timestamptz) to authenticated;
grant execute on function public.ingest(bytea, jsonb) to service_role;
