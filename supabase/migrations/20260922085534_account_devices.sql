-- Machines, and how one comes to belong to an account.
--
-- The machine starts it: `pokegosu auth login` draws a short code and waits.
-- The person reads that code off their own terminal, opens the web and
-- approves it; the machine then collects a key of its own. The key says which
-- account and which machine, and every service reads it the same way, so a
-- machine is enrolled once rather than once per service.
--
-- The web reads and changes its own machines directly under RLS. A machine
-- cannot: it has nothing to authenticate with until it is enrolled, so its
-- two steps go through Edge Functions and the functions below.

-- ============================================================
-- devices: a machine, and the credential it speaks with.
--
-- The machine makes up its own id on first run and keeps it; the server
-- learns it when the machine asks to be enrolled.
--
-- The credential lives here rather than in a table of its own because it
-- belongs to exactly one machine. One lookup on api_key_hash answers both
-- "which account" and "which machine", which is everything an upload
-- needs, and revoking a machine is revoking its key.
--
-- What that buys is only half enforced here, and the halves are worth
-- keeping straight. A service's rows can name a machine AND an owner
-- together, and the schema then stops one account's name over another
-- account's machine. It cannot stop a machine from writing a SIBLING
-- machine's rows — that holds only while a service takes device_id from this
-- lookup and never from the request.
--
-- Only the hash is stored. The plaintext goes to the machine once, when it
-- collects the key, and never again.
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

  -- What a service's rows point at: naming the machine and the owner
  -- together is what stops the two from disagreeing.
  unique (id, user_id)
);

create index on public.devices (user_id);


-- ============================================================
-- enrollments: a machine asking to be let in, and waiting to be let in.
--
-- The machine starts it. `pokegosu auth login` draws a short code, keeps it,
-- and leaves a row here; the person reads the code off their own terminal and
-- approves it in the web, which is the only step that needs an account. The
-- machine polls until the row says yes and then collects its key.
--
-- Nothing here is a credential a person carries. The code is worth little —
-- it lives ten minutes, works once, and approving it takes a signed-in
-- person. The machine proves it is the one that asked with claim_hash, which
-- the server made and only the machine ever saw.
--
-- Two hashes and no plaintext, for the same reason the device key is stored
-- as a digest: a leak of this table is worth nothing.
-- ============================================================
create table public.enrollments (
  code_hash   bytea primary key
                constraint code_hash_is_sha256
                check (octet_length(code_hash) = 32),

  -- What the machine shows to collect its key. Server-made, so guessing the
  -- code a person is reading aloud is not enough to steal the enrolment.
  claim_hash  bytea not null unique
                constraint claim_hash_is_sha256
                check (octet_length(claim_hash) = 32),

  -- The machine's own id and what it calls itself, carried from the start so
  -- the approving screen can say which machine this is.
  device_id   uuid not null,
  device_name text not null
                constraint device_name_is_legible
                check (device_name ~ '[^[:space:]]' and length(device_name) <= 100),

  -- Null until a person approves it; then whose it is.
  user_id     uuid references auth.users on delete cascade,
  approved_at timestamptz,

  expires_at  timestamptz not null,
  created_at  timestamptz not null default now(),

  -- Approved means both, or neither: a row cannot name an owner without the
  -- moment they said so.
  constraint approval_is_whole
    check ((user_id is null) = (approved_at is null)),

  -- A request that is born expired could never be approved.
  constraint request_outlives_its_making check (expires_at > created_at)
);

-- Sweeping expired rows walks this.
create index on public.enrollments (expires_at);


-- ============================================================
-- Access.
--
-- auto_expose_new_tables being off is not quite "no grants": it still hands
-- anon and authenticated TRUNCATE, REFERENCES, TRIGGER and MAINTAIN on every
-- new table. PostgREST never issues those, but RLS does not apply to
-- TRUNCATE, so everything is taken away first and only what the web needs is
-- given back, column by column.
-- ============================================================
revoke all on public.devices, public.enrollments from anon, authenticated;

alter table public.devices     enable row level security;
alter table public.enrollments enable row level security;

-- A person sees their own machines, and may rename or retire one. The key
-- digest is left out of the grant: a browser has no use for it.
grant select (id, name, revoked_at, last_sync_at, created_at) on public.devices to authenticated;
grant update (name, revoked_at) on public.devices to authenticated;

-- auth.uid() is wrapped in a subquery so Postgres evaluates it once per
-- statement rather than once per row.
create policy "owners can read their devices"
  on public.devices for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "owners can rename or retire their devices"
  on public.devices for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- enrollments gets nothing: only the functions below touch it. A person
-- approves through approve_enrollment, never by writing the row.


-- ============================================================
-- Retiring a machine is one way, for the person doing it.
--
-- Setting revoked_at through the API retires a machine; clearing it would
-- bring back a key the person meant to kill, and a timestamp in the future
-- would read as retired while meaning nothing. So the column takes now()
-- when set, and cannot be cleared or moved afterwards. RLS cannot say this —
-- an UPDATE policy's WITH CHECK never sees the old row — so it takes a
-- trigger, the same way profiles keeps a username.
--
-- Enrolling the machine again, with a fresh code, is how it comes back.
-- claim_enrollment does that as the table's owner, which is why the
-- rule applies to authenticated alone.
-- ============================================================
create function public.enforce_device_retirement()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user <> 'authenticated' then
    return new;
  end if;

  if old.revoked_at is not null and new.revoked_at is distinct from old.revoked_at then
    raise exception 'a retired machine comes back by enrolling it again, not by clearing revoked_at';
  end if;
  if old.revoked_at is null and new.revoked_at is not null then
    new.revoked_at := now();
  end if;
  return new;
end;
$$;

create trigger devices_retirement_is_one_way
  before update on public.devices
  for each row execute function public.enforce_device_retirement();


-- ============================================================
-- normalize_code turns what a person typed into what the machine drew, or
-- into something that will simply not be found.
--
-- The alphabet a machine draws from has no I, L, O or U, so someone who reads
-- a 1 as an I should not be told their code is wrong: those letters fold back
-- to the digits they were mistaken for. Anything else — spaces, the dash, a
-- stray quote — is dropped. It does not judge the input: a wrong length makes
-- a string no digest matches, and "no such request" is the honest answer to
-- both a typo and a guess.
--
-- Not granted to anyone: the functions below run as their owner and are the
-- only callers.
-- ============================================================
create function public.normalize_code(typed text)
returns bytea
language sql
immutable
set search_path = ''
as $$
  select sha256(convert_to(
           regexp_replace(translate(upper(typed), 'ILO', '110'), '[^0-9A-Z]', '', 'g'),
           'UTF8'));
$$;


-- ============================================================
-- start_enrollment — a machine asks to be let in.
--
-- Called by the start-enrollment Edge Function, which drew nothing itself:
-- the code is the machine's, and the claim token is the server's. Both arrive
-- hashed.
--
--   → {"outcome": "started", "expires_at": "..."}
--   → {"outcome": "code_taken"}  another machine is waiting on that code;
--                                the caller draws again
-- ============================================================
create function public.start_enrollment(
  code_hash bytea, claim_hash bytea, device_id uuid, device_name text, lifetime interval)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  expiry timestamptz := now() + lifetime;
begin
  -- Nothing else sweeps these, and a request nobody approved is rubbish after
  -- its ten minutes. Doing it here keeps the table the size of what is
  -- actually being enrolled right now.
  delete from public.enrollments where expires_at < now();

  insert into public.enrollments (code_hash, claim_hash, device_id, device_name, expires_at)
  values (start_enrollment.code_hash, start_enrollment.claim_hash,
          start_enrollment.device_id, start_enrollment.device_name, expiry);

  return jsonb_build_object(
    'outcome', 'started',
    'expires_at', to_char(expiry at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
exception when unique_violation then
  -- One in a trillion for the code, and impossible for the claim token, but
  -- both mean the same thing to the caller: draw again.
  return jsonb_build_object('outcome', 'code_taken');
end;
$$;


-- ============================================================
-- pending_enrollment — what the web shows before anyone approves anything.
--
--   → {"outcome": "pending", "device_name": "laptop", "requested_at": "..."}
--   → {"outcome": "not_found"}   expired, spent, or never asked for
--
-- A person must be able to see which machine they are about to let in, so
-- this is readable by anyone signed in. It says nothing about who asked,
-- because nobody has: a request belongs to no account until it is approved.
-- ============================================================
create function public.pending_enrollment(code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  found record;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  select e.device_name, e.created_at, e.user_id into found
    from public.enrollments e
   where e.code_hash = public.normalize_code(pending_enrollment.code)
     and e.expires_at > now();

  if found is null or found.user_id is not null then
    return jsonb_build_object('outcome', 'not_found');
  end if;

  return jsonb_build_object(
    'outcome', 'pending',
    'device_name', found.device_name,
    'requested_at', to_char(found.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'));
end;
$$;


-- ============================================================
-- approve_enrollment — a person lets a machine in.
--
--   → {"outcome": "approved", "device_name": "laptop"}
--   → {"outcome": "not_found"}   expired, already approved, or never asked for
--
-- This is the whole of what a session is for here. The machine's key is not
-- made yet and never passes through this browser: the machine collects it
-- afterwards, with the claim token only it holds.
-- ============================================================
create function public.approve_enrollment(code text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  caller uuid := auth.uid();
  approved record;
begin
  if caller is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  -- One statement: a request can only be approved once, and only while it is
  -- unapproved and unexpired. Reading it and then updating it would let two
  -- tabs approve the same request for two accounts.
  update public.enrollments e
     set user_id = caller, approved_at = now()
   where e.code_hash = public.normalize_code(approve_enrollment.code)
     and e.expires_at > now()
     and e.user_id is null
  returning e.device_name into approved;

  if approved is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  return jsonb_build_object('outcome', 'approved', 'device_name', approved.device_name);
end;
$$;


-- ============================================================
-- claim_enrollment — the machine collects what it was promised.
--
-- Called by the claim-enrollment Edge Function on every poll, with a freshly
-- minted key. The key is made at this moment, for this machine, and goes
-- nowhere else; only its digest stays here.
--
--   → {"outcome": "registered", "user_id": "...", "device_name": "laptop"}
--   → {"outcome": "waiting"}      nobody has approved it yet
--   → {"outcome": "not_found"}    expired, or already collected
--   → {"outcome": "device_taken"} that machine belongs to another account
--
-- A machine the same account already registered is enrolled again with the
-- new key, which is how a retired machine, or one that lost its settings but
-- kept its id, comes back. It keeps its id, and so its history.
-- ============================================================
create function public.claim_enrollment(claim_hash bytea, api_key_hash bytea)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  request record;
  registered uuid;
begin
  select e.code_hash, e.device_id, e.device_name, e.user_id into request
    from public.enrollments e
   where e.claim_hash = claim_enrollment.claim_hash
     and e.expires_at > now();

  if request is null then
    return jsonb_build_object('outcome', 'not_found');
  end if;
  if request.user_id is null then
    return jsonb_build_object('outcome', 'waiting');
  end if;

  insert into public.devices as d (id, user_id, name, api_key_hash)
  values (request.device_id, request.user_id, request.device_name, claim_enrollment.api_key_hash)
  on conflict (id) do update
    set name = excluded.name,
        api_key_hash = excluded.api_key_hash,
        revoked_at = null
    where d.user_id = excluded.user_id
  returning d.id into registered;

  -- Nothing came back: the id is taken, and not by this account. The request
  -- stays, so a person can see it is still waiting rather than having it
  -- vanish; it expires on its own.
  if registered is null then
    return jsonb_build_object('outcome', 'device_taken');
  end if;

  -- Collected once: the claim token is spent along with the request.
  delete from public.enrollments e where e.code_hash = request.code_hash;

  return jsonb_build_object(
    'outcome', 'registered',
    'user_id', request.user_id,
    'device_name', request.device_name);
end;
$$;


-- ============================================================
-- Who may call what.
--
-- Postgres lets PUBLIC execute every new function, and anon and authenticated
-- are members of PUBLIC. So each function has its execute revoked from PUBLIC
-- and granted back to exactly the role that calls it. A function added later
-- needs the same; the tests check every function in public, not just these.
-- ============================================================
revoke execute on function
  public.normalize_code(text),
  public.start_enrollment(bytea, bytea, uuid, text, interval),
  public.pending_enrollment(text),
  public.approve_enrollment(text),
  public.claim_enrollment(bytea, bytea),
  public.enforce_device_retirement()
  from public;

grant execute on function public.pending_enrollment(text) to authenticated;
grant execute on function public.approve_enrollment(text) to authenticated;
grant execute on function public.start_enrollment(bytea, bytea, uuid, text, interval) to service_role;
grant execute on function public.claim_enrollment(bytea, bytea) to service_role;
