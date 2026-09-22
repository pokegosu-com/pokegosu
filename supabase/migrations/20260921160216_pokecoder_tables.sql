-- pokecoder: coding agent token usage, collected from every machine a person
-- works on. A machine enrols with a short code and uploads hourly totals; the
-- web reads them back. All of it goes through the pokecoder API app and the
-- functions in the `pokecoder` schema (next migration), so nothing here is
-- granted to a client role.

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
-- devices: a machine, and the credential it speaks with.
--
-- The machine makes up its own id on first run and keeps it; the server
-- learns it when an enrollment code is redeemed.
--
-- The credential lives here rather than in a table of its own because it
-- belongs to exactly one machine. One lookup on api_key_hash answers both
-- "which account" and "which machine", which is everything an upload
-- needs, and revoking a machine is revoking its key.
--
-- What that buys is only half enforced here, and the halves are worth
-- keeping straight. The schema stops a row from naming one account over
-- another account's machine (see usage_rollups). It cannot stop a machine
-- from writing a SIBLING machine's rows — that holds only while pokecoder.ingest
-- takes device_id from this lookup and never from the request.
--
-- Only the hash is stored. The plaintext is shown once, at enrollment,
-- and never again.
-- ============================================================
create table public.devices (
  id           uuid primary key,
  user_id      uuid not null references auth.users on delete cascade,
  name         text not null
                 constraint device_name_is_legible
                 check (name ~ '[^[:space:]]' and length(name) <= 100),
  api_key_hash bytea not null unique
                 constraint api_key_hash_is_sha256
                 check (octet_length(api_key_hash) = 32),
  revoked_at   timestamptz,
  last_sync_at timestamptz,
  created_at   timestamptz not null default now(),

  -- What usage_rollups points at. A rollup names a machine AND an owner,
  -- and referencing the pair is what stops the two from disagreeing.
  unique (id, user_id)
);

create index on public.devices (user_id);


-- ============================================================
-- enrollment_codes: what carries an account from the browser to a machine.
--
-- A signed-in person asks the web for a code and types it into the CLI,
-- which trades it for a credential of its own. The code is the only thing
-- that passes through a person's hands, and it is worth little: it lives
-- for minutes, works once, and is deleted as it is spent.
--
-- Only the hash is stored, for the same reason the device key is.
--
-- Two rules this table cannot keep on its own, and
-- pokecoder.create_enrollment_code and pokecoder.redeem_enrollment_code keep
-- them:
--
--   Minting reuses the slot. unique (user_id) holds an account to one
--   ROW, not to one live code, and nothing sweeps a code that was minted
--   and never typed in. A plain insert therefore fails against a code
--   that expired weeks ago, and that is a lockout with no way out.
--
--   Redemption deletes and reads in one statement. Reading the row and
--   then deleting it lets two machines redeem the same code.
-- ============================================================
create table public.enrollment_codes (
  code_hash  bytea primary key
               constraint code_hash_is_sha256
               check (octet_length(code_hash) = 32),
  user_id    uuid not null unique references auth.users on delete cascade,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),

  -- A code that is born expired would take the account's one slot and
  -- never be redeemable.
  constraint code_outlives_its_making check (expires_at > created_at)
);


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
-- Access.
--
-- No client role reads or writes these tables. Every request goes through the
-- pokecoder API app, which checks it and then calls a function in the
-- `pokecoder` schema (next migration); those functions run as their owner.
--
-- auto_expose_new_tables being off is not quite "no grants": it still hands
-- anon and authenticated TRUNCATE, REFERENCES, TRIGGER and MAINTAIN on every
-- new table. PostgREST never issues any of those, but RLS does not apply to
-- TRUNCATE, so they are taken away here rather than trusted to stay out of
-- reach. RLS is enabled with no policies as well, so that a grant added later
-- by mistake still reaches nothing.
-- ============================================================
revoke all on public.providers, public.devices, public.enrollment_codes, public.usage_rollups
  from anon, authenticated;

alter table public.providers        enable row level security;
alter table public.devices          enable row level security;
alter table public.enrollment_codes enable row level security;
alter table public.usage_rollups    enable row level security;
