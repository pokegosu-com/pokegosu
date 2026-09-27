-- ============================================================
-- usage — now split by coding agent, and over up to a calendar month.
--
--   → {"from": "...", "to": "...", "total": "123",
--      "providers": [{"provider", "display_name", "tokens"}],
--      "devices":   [{"device_id", "device_name", "tokens", "providers": {"<provider>": tokens}}],
--      "hours":     [{"hour_bucket", "tokens", "providers": {"<provider>": tokens}}]}
--
-- The usage screen colours each agent's share of an hour, a day and a
-- machine, so every sum also comes split by provider. Only the providers with
-- tokens in that row appear in its object; the top-level list names every
-- provider in the range, busiest first, for the legend. Days are left to the
-- screen: which hours make a day depends on where the person is.
--
-- The longest range grows from 30 days to 31, so the longest month is one
-- call. That is 744 hourly buckets per machine, still what a screen of hours
-- can show.
--
-- Everything else is as before: it runs as its caller, so RLS limits it to
-- the caller's rows, and the grand total is a string because a lifetime
-- total can pass 2^53.
-- ============================================================
create or replace function public.usage(range_start timestamptz, range_end timestamptz)
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
  if range_end - range_start > interval '31 days' then
    raise exception 'the range is longer than 31 days' using errcode = '22023';
  end if;

  return (
    with ledger as (
      select r.device_id, r.provider, r.hour_bucket, r.tokens::bigint as tokens
        from public.usage_rollups r
       where r.hour_bucket >= range_start and r.hour_bucket < range_end
    ),
    by_provider as (
      select l.provider, p.display_name, sum(l.tokens) as tokens
        from ledger l
        join public.providers p on p.id = l.provider
       group by l.provider, p.display_name
    ),
    by_device as (
      select l.device_id, d.name, sum(l.tokens) as tokens,
             (select jsonb_object_agg(s.provider, s.tokens)
                from (select l2.provider, sum(l2.tokens) as tokens
                        from ledger l2 where l2.device_id = l.device_id
                       group by l2.provider) s) as providers
        from ledger l
        left join public.devices d on d.id = l.device_id
       group by l.device_id, d.name
    ),
    by_hour as (
      select l.hour_bucket, sum(l.tokens) as tokens,
             (select jsonb_object_agg(s.provider, s.tokens)
                from (select l2.provider, sum(l2.tokens) as tokens
                        from ledger l2 where l2.hour_bucket = l.hour_bucket
                       group by l2.provider) s) as providers
        from ledger l
       group by l.hour_bucket
    )
    select jsonb_build_object(
      'from', to_char(range_start at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'to', to_char(range_end at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
      'total', coalesce((select sum(l.tokens) from ledger l), 0)::text,
      'providers', coalesce((
        select jsonb_agg(
                 jsonb_build_object('provider', b.provider, 'display_name', b.display_name, 'tokens', b.tokens)
                 order by b.tokens desc, b.provider)
          from by_provider b), '[]'::jsonb),
      'devices', coalesce((
        select jsonb_agg(
                 jsonb_build_object('device_id', b.device_id, 'device_name', b.name, 'tokens', b.tokens,
                                    'providers', b.providers)
                 order by b.tokens desc, b.device_id::text)
          from by_device b), '[]'::jsonb),
      'hours', coalesce((
        select jsonb_agg(
                 jsonb_build_object(
                   'hour_bucket', to_char(h.hour_bucket at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                   'tokens', h.tokens,
                   'providers', h.providers)
                 order by h.hour_bucket)
          from by_hour h), '[]'::jsonb))
  );
end;
$$;
