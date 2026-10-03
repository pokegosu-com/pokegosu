-- An hour counts once it is over. A Pokémon sent at 14:50 starts at 0 hours,
-- and the 14:00 hour becomes its first at 15:00, if there was usage in it.
-- Counting the hour in progress put a Pokémon at 1 the moment it was sent,
-- from usage before it went, and moved every count an hour ahead of the
-- clock: eight hours of work were done before eight hours had passed.
--
-- The same goes for a request on its way after a reroll and the person's
-- own hours, since all three count through active_hours().


-- ============================================================
-- active_hours — the hours with any usage from the one a moment falls in up
-- to the one in progress, which is left out until it ends. The first hour
-- still counts even if its usage came before the moment, so an hour can count
-- for both the shift that ends in it and the one that starts: better than a
-- person seeing work they did go unpaid.
-- ============================================================
create or replace function public.active_hours(owner uuid, since timestamptz)
returns integer
language sql
stable
set search_path = ''
as $$
  select count(distinct r.hour_bucket)::integer
    from public.usage_rollups r
   where r.user_id = owner and r.tokens > 0
     and r.hour_bucket >= date_trunc('hour', since, 'UTC')
     and r.hour_bucket < date_trunc('hour', now(), 'UTC');
$$;
