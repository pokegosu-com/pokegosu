-- Every baby is rare, whatever it grows into.
--
-- Until now a baby took the tier of what it grows into, so Togepi was very
-- rare and Igglybuff, Smoochum, Elekid, Magby, Azurill and Wynaut uncommon.
-- A baby is now a find of its own, rare alike. What a baby grows into keeps
-- its tier where an egg holds it, as a Kanto egg holds Pikachu.
update public.coder_species_rarities r
   set rarity = 'rare'
  from public.pokedex_species s
 where s.id = r.species_id and s.category = 'baby';
