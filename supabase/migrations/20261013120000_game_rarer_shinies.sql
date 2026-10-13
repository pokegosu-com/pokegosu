-- A shiny Pokémon is half as likely: an egg holds one one time in 128, and
-- one time in 64 for someone who holds the Shiny Charm, which still doubles
-- the odds. Shiny Pokémon came too often to be the rare find they are in the
-- games.
--
-- A request's client is shiny as often as an egg without the charm is, so it
-- is now one time in 128 too. Eggs and requests already drawn stay as they
-- are.

update public.coder_settings set shiny_odds = 128, charm_shiny_odds = 64;
