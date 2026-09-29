-- A display name is no longer optional: whoever has a handle has a name, and
-- one left blank is the handle as it is shown, `@abc`. It can still be null
-- before the handle is set, since the row exists from the moment the auth
-- user does and nothing is known about them yet.

-- A trigger rather than a client default, so onboarding, clearing the name
-- later and any other writer all land on the same rule.
create function public.default_display_name()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.username is not null and coalesce(btrim(new.display_name), '') = '' then
    new.display_name := '@' || new.username;
  end if;
  return new;
end;
$$;

create trigger profiles_default_display_name
  before insert or update on public.profiles
  for each row execute function public.default_display_name();

update public.profiles
   set display_name = '@' || username
 where username is not null
   and coalesce(btrim(display_name), '') = '';

alter table public.profiles
  add constraint profiles_display_name_required
    check (username is null or btrim(display_name) <> '');
