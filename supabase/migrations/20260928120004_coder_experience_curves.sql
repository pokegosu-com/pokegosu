-- The experience curve and eggs take twice the tokens, and the curve has
-- the two growth rates Hoenn brought: Erratic and Fluctuating, PokéAPI's
-- slow-then-very-fast and fast-then-very-slow. The curve was written before
-- they came, so a Pokémon growing at either had no rows: it never levelled
-- and the box left it out.
--
-- Medium Fast now reaches Lv.50 on 400M tokens and Lv.100 on 1B. The four
-- rates there were keep their shape, doubled. An egg cycle is 2M tokens.
--
-- Erratic and Fluctuating are what their shape is: Erratic slow early and
-- very fast late, Fluctuating the other way round. The other rates only
-- differ from Medium Fast by a constant, so they share its shape. These two
-- take Medium Fast's tokens times how far the games put them from it at
-- each level, softened to the power 0.7, and reach Lv.100 in the games'
-- proportion. At 1, Erratic's last levels would cost less than the one
-- before.
--
--   tokens(level) = medium(level) × ratio(level) ^ 0.7 × ratio(100) ^ 0.3,
--   ratio(level) = the games' exp at level / Medium Fast's
--
-- What a companion has taken is doubled with it: its egg tokens, its
-- experience and its invested tokens alike, as a token stays a point of
-- experience. Every egg keeps how far it is from hatching and every Pokémon
-- its level, and what was invested weighs twice on the balance, which can
-- go below zero until usage makes it up. An Erratic or Fluctuating Pokémon
-- reaches the level its doubled experience buys, and gives back as balance
-- whatever went past Lv.100.

update public.coder_settings set tokens_per_cycle = tokens_per_cycle * 2;

update public.coder_experience_levels set tokens = tokens * 2;

update public.coder_companions
   set egg_tokens = egg_tokens * 2,
       exp = exp * 2,
       invested_tokens = invested_tokens * 2;

insert into public.coder_experience_levels (growth_rate, level, tokens)
select g.growth_rate, g.level,
       case when g.level = 1 then 0
            else round(m.tokens * power(g.exp::numeric / gm.exp, 0.7)
                                * power(top.exp::numeric / topm.exp, 0.3)) end
  from public.pokedex_experience_levels g
  join public.pokedex_experience_levels gm on gm.growth_rate = 'medium' and gm.level = g.level
  join public.coder_experience_levels m on m.growth_rate = 'medium' and m.level = g.level
  join public.pokedex_experience_levels top on top.growth_rate = g.growth_rate and top.level = 100
  join public.pokedex_experience_levels topm on topm.growth_rate = 'medium' and topm.level = 100
 where g.growth_rate in ('slow-then-very-fast', 'fast-then-very-slow');

with top as (
  select growth_rate, tokens from public.coder_experience_levels where level = 100
)
update public.coder_companions c
   set level = greatest(c.level,
                        (select max(e.level) from public.coder_experience_levels e
                          where e.growth_rate = p.growth_rate and e.tokens <= c.exp)),
       invested_tokens = c.invested_tokens - greatest(0, c.exp - top.tokens),
       exp = least(c.exp, top.tokens)
  from public.pokedex_species p, top
 where p.id = c.species_id
   and top.growth_rate = p.growth_rate
   and c.hatched_at is not null
   and p.growth_rate in ('slow-then-very-fast', 'fast-then-very-slow');
