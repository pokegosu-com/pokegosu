-- The Helper Ribbon: for a Pokémon that has done ten requests. Only the tenth
-- earns one; there is no ribbon for the fiftieth or the hundredth.
--
-- Requests are counted from coder_requests_done, so those settled before it
-- was made do not count.

insert into public.coder_ribbons (id, ko_name, en_name, ko_description, en_description) values
  ('helper', '도우미 리본', 'Helper Ribbon',
   '의뢰를 10번 해낸 포켓몬에게 주는 리본', 'A ribbon for a Pokémon that has done 10 requests');

create or replace function public.eligible_ribbons(pokemon public.coder_companions)
returns text[]
language sql
stable
set search_path = ''
as $$
  select coalesce(array_agg(r.id order by r.id), '{}')
    from public.coder_ribbons r
   where case r.id
           when 'level-100' then pokemon.level = 100
           when 'helper' then (select count(*) from public.coder_requests_done d
                                where d.companion_id = pokemon.id) >= 10
           else false
         end
     and not exists (
           select 1 from public.coder_companion_ribbons cr
            where cr.companion_id = pokemon.id and cr.ribbon_id = r.id);
$$;
