-- The experience curve takes twice the tokens, and has the two growth rates
-- Hoenn brought: Erratic and Fluctuating, PokéAPI's slow-then-very-fast and
-- fast-then-very-slow. The curve was written before they came, so a Pokémon
-- growing at either had no rows: it never levelled and the box left it out.
--
-- Medium Fast now reaches Lv.50 on 400M tokens and Lv.100 on 1B. The four
-- rates there were keep their shape, doubled.
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
-- Nothing already earned is lost. A Pokémon of the four rates keeps its
-- level and how far it is into the next, its experience doubled with the
-- curve. One of the two new rates keeps the tokens it took, and they now
-- count: it reaches the level they buy, and takes back as balance whatever
-- went past Lv.100.

update public.coder_experience_levels set tokens = tokens * 2;

update public.coder_companions c
   set exp = c.exp * 2
  from public.pokedex_species p
 where p.id = c.species_id
   and c.hatched_at is not null
   and p.growth_rate in (select distinct growth_rate from public.coder_experience_levels);

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
