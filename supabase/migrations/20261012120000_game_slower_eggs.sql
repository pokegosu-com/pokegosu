-- An egg takes two and a half times the tokens, and the experience curve a
-- tenth fewer. Eggs hatched too fast: the usual one, of 20 cycles, took 40M
-- tokens, which is less than Lv.10 does.
--
-- An egg cycle is now 5M tokens, so the usual egg takes 100M. Medium Fast
-- reaches Lv.50 on 360M and Lv.100 on 900M, and the egg and the curve
-- together come to the 1B the curve alone took. Every growth rate keeps its
-- shape and its distance from Medium Fast.
--
-- An egg not yet hatched keeps the tokens it has taken, so it is as much
-- further from hatching as the cycle is longer. Keeping how far along it was
-- would take tokens from the balance for an egg the person has yet to see.
--
-- A Pokémon keeps its level and how far it is through it. Its experience is
-- a tenth less, and those tokens go back to the balance. What its egg took
-- is multiplied with the cycle and taken from the balance, so a Pokémon
-- hatched before today has cost what one hatched after it will: the usual
-- one at Lv.100 on Medium Fast has 1B invested either way. The balance can
-- go below zero until usage makes it up. What was invested moves with both,
-- as a token stays a point of experience.

update public.coder_settings set tokens_per_cycle = 5000000;

update public.coder_companions
   set egg_tokens = egg_tokens * 5 / 2,
       invested_tokens = invested_tokens + egg_tokens * 5 / 2 - egg_tokens
 where hatched_at is not null;

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
