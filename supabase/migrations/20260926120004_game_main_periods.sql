-- coder_main_periods: when each companion was a person's main.
--
-- Friendship will grow with time spent together, as walking with a Pokémon
-- grows it in the games, and here being together is coding while it is the
-- main. usage_rollups already says in which hours a person coded; this says
-- who was the main then. The two are kept as facts and friendship is worked
-- out from them later, so how an hour counts can be decided, and changed,
-- without losing what came before.
--
-- A trigger on coder_trainers writes it, so every way the main changes, now
-- or later, is kept alike. A period still open has no ended_at, and a person
-- has at most one of those. Mains from before this migration are opened
-- from now: when they became the main was not kept.
--
-- Nothing reads it yet, and nobody is granted it.

create table public.coder_main_periods (
  id           bigint generated always as identity primary key,
  companion_id uuid not null,
  user_id      uuid not null,
  started_at   timestamptz not null default now(),
  ended_at     timestamptz,
  foreign key (companion_id, user_id) references public.coder_companions (id, user_id) on delete cascade,
  constraint ends_after_it_starts check (ended_at >= started_at)
);

create unique index coder_main_periods_one_open_per_person on public.coder_main_periods (user_id)
  where ended_at is null;
create index on public.coder_main_periods (companion_id);

revoke all on public.coder_main_periods from anon, authenticated;
alter table public.coder_main_periods enable row level security;


create function public.record_main_period()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.coder_main_periods p set ended_at = now()
   where p.user_id = new.user_id and p.ended_at is null;
  insert into public.coder_main_periods (companion_id, user_id)
  values (new.main_companion_id, new.user_id);
  return null;
end;
$$;

revoke execute on function public.record_main_period() from public;

create trigger record_first_main
  after insert on public.coder_trainers
  for each row execute function public.record_main_period();

-- Choosing the main that already is one goes on with the same period.
create trigger record_main_period
  after update of main_companion_id on public.coder_trainers
  for each row when (old.main_companion_id is distinct from new.main_companion_id)
  execute function public.record_main_period();

insert into public.coder_main_periods (companion_id, user_id)
select t.main_companion_id, t.user_id from public.coder_trainers t;
