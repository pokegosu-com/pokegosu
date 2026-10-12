-- An egg takes two and a half times the tokens, and the experience curve a
-- tenth fewer. Eggs hatched too fast: the usual one, of 20 cycles, took 40M
-- tokens, which is less than Lv.10 does.
--
-- An egg cycle is now 5M tokens, so the usual egg takes 100M. Medium Fast
-- reaches Lv.50 on 360M and Lv.100 on 900M, and the egg and the curve
-- together come to the 1B the curve alone took. Every growth rate keeps its
-- shape and its distance from Medium Fast.
--
-- An egg not yet hatched keeps how far it is from hatching, as it did when
-- the curve was doubled: its tokens are multiplied with the cycle, and what
-- was invested in it with them, which can take the balance below zero until
-- usage makes it up.
--
-- A Pokémon keeps its level and how far it is through it. Its experience is
-- a tenth less, and what was invested in it less by the same tokens, which
-- go back to the balance. What its egg took stays what it took: that egg
-- hatched at the old price, and charging for it again would take from the
-- balance for nothing the person can see.

update public.coder_settings set tokens_per_cycle = 5000000;

update public.coder_companions
   set egg_tokens = egg_tokens * 5 / 2,
       invested_tokens = invested_tokens + egg_tokens * 5 / 2 - egg_tokens
 where hatched_at is null;

update public.coder_experience_levels set tokens = round(tokens * 0.9);

-- Rounding the curve and the experience apart could leave a Pokémon a token
-- short of the level it has, or a token into the next, so its experience is
-- held between where its level starts and where the next one does.
with scaled as (
  select c.id,
         least(greatest(round(c.exp * 0.9)::bigint, here.tokens),
               coalesce(next.tokens - 1, here.tokens)) as exp
    from public.coder_companions c
    join public.pokedex_species p on p.id = c.species_id
    join public.coder_experience_levels here
      on here.growth_rate = p.growth_rate and here.level = c.level
    left join public.coder_experience_levels next
      on next.growth_rate = p.growth_rate and next.level = c.level + 1
   where c.hatched_at is not null
)
update public.coder_companions c
   set invested_tokens = c.invested_tokens + s.exp - c.exp,
       exp = s.exp
  from scaled s
 where s.id = c.id;
