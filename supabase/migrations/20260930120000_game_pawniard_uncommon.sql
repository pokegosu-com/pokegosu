-- Pawniard is uncommon, not rare.
--
-- Generation V's rarities made it rare by feel, as they did Yamask and
-- Larvesta. On a second look it sits better with the uncommon ones.
update public.coder_species_rarities r
   set rarity = 'uncommon'
  from public.pokedex_species s
 where s.id = r.species_id and s.slug = 'pawniard';
