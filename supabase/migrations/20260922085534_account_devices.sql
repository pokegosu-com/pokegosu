-- Machines, and how one comes to belong to an account.
--
-- A person adds a machine in the web, which shows a short code; the machine
-- trades that code for a key of its own. The key says which account and which
-- machine, and every service reads it the same way, so a machine is enrolled
-- once rather than once per service.
--
-- The web reads and changes its own machines directly under RLS. Redeeming
-- cannot: it happens before the machine has anything to authenticate with, so
-- it goes through an Edge Function and the function below.

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
-- keeping straight. A service's rows can name a machine AND an owner
-- together, and the schema then stops one account's name over another
-- account's machine. It cannot stop a machine from writing a SIBLING
-- machine's rows — that holds only while a service takes device_id from this
-- lookup and never from the request.
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

  -- What a service's rows point at: naming the machine and the owner
  -- together is what stops the two from disagreeing.
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
-- Two rules this table cannot keep on its own, and create_enrollment_code
-- and redeem_enrollment_code keep them:
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
-- Access.
--
-- auto_expose_new_tables being off is not quite "no grants": it still hands
-- anon and authenticated TRUNCATE, REFERENCES, TRIGGER and MAINTAIN on every
-- new table. PostgREST never issues those, but RLS does not apply to
-- TRUNCATE, so everything is taken away first and only what the web needs is
-- given back, column by column.
-- ============================================================
revoke all on public.devices, public.enrollment_codes from anon, authenticated;

alter table public.devices          enable row level security;
alter table public.enrollment_codes enable row level security;

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

-- enrollment_codes gets nothing: only the functions below touch it.


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
-- redeem_enrollment_code does that as the table's owner, which is why the
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
-- Who may call what.
--
-- Postgres lets PUBLIC execute every new function, and anon and authenticated
-- are members of PUBLIC. So each function has its execute revoked from PUBLIC
-- and granted back to exactly the role that calls it. A function added later
-- needs the same; the tests check every function in public, not just these.
-- ============================================================
revoke execute on function
  public.create_enrollment_code(),
  public.redeem_enrollment_code(bytea, uuid, text, bytea),
  public.enforce_device_retirement()
  from public;

grant execute on function public.create_enrollment_code() to authenticated;
grant execute on function public.redeem_enrollment_code(bytea, uuid, text, bytea) to service_role;
