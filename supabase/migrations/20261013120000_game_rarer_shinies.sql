-- An egg is half as likely to hold a shiny Pokémon: one time in 128, and one
-- time in 64 for someone who holds the Shiny Charm, which still doubles the
-- odds. Shiny Pokémon hatched too often to be the rare find they are in the
-- games.
--
-- A request's client is shiny one time in 64, as before. It was drawn at an
-- egg's odds, so it now has its own, beside the rest in coder_settings. Eggs
-- and requests already drawn stay as they are.

alter table public.coder_settings
  -- A request's client is shiny one time in this many.
  add column client_shiny_odds integer not null default 64 check (client_shiny_odds >= 1);

alter table public.coder_settings
  alter column client_shiny_odds drop default;

update public.coder_settings set shiny_odds = 128, charm_shiny_odds = 64;

-- Whether a client drawn now is shiny: one time in client_shiny_odds.
create or replace function public.roll_shiny()
returns boolean
language sql
volatile
set search_path = ''
as $$
  select floor(random() * g.client_shiny_odds) = 0 from public.coder_settings g;
$$;
