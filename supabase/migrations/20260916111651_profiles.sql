-- auth.users is not exposed through PostgREST and cannot be joined against,
-- and raw_user_meta_data is rewritable by the user with nothing but their own
-- access token. Queryable, trustworthy profile data needs its own table.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,

  -- Null until chosen: the row is created the moment the auth user exists.
  -- account-web asks for both on first sign-in.
  username text unique,
  display_name text,

  constraint profiles_username_format
    check (username is null or username ~ '^[a-z0-9_-]{3,30}$')
);

alter table public.profiles enable row level security;

-- auth.uid() is wrapped in a subquery so Postgres evaluates it once per
-- statement rather than once per row.
create policy "owners can read their profile"
  on public.profiles for select
  to authenticated
  using ((select auth.uid()) = id);

create policy "owners can create their profile"
  on public.profiles for insert
  to authenticated
  with check ((select auth.uid()) = id);

create policy "owners can update their profile"
  on public.profiles for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- No delete policy on purpose: nothing can delete through the API, and the
-- cascade above removes the row along with the user.

-- A handle is permanent once set. RLS cannot express this — an UPDATE policy's
-- WITH CHECK never sees the old row — so it takes a trigger.
create function public.enforce_username_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.username is not null and new.username is distinct from old.username then
    raise exception 'username cannot be changed once set';
  end if;
  return new;
end;
$$;

create trigger profiles_username_immutable
  before update on public.profiles
  for each row execute function public.enforce_username_immutable();

-- Every auth user gets a row immediately, so no client has to handle "signed
-- in but no profile". It writes the id and nothing else: a failure here rolls
-- back the signup itself.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
