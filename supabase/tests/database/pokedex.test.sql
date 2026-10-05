-- The pokedex_ tables: reference data anyone may read and nobody may change.

begin;

create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(76);

select is((select count(*)::int from public.pokedex_species where generation = 1 and form_of is null), 151,
  'every Generation I species has its default form');
select is((select count(*)::int from public.pokedex_species where generation = 2 and form_of is null), 100,
  'and every Generation II species');
select is((select count(*)::int from public.pokedex_species where generation = 3 and form_of is null), 135,
  'and every Generation III species');
select is((select count(*)::int from public.pokedex_species where generation = 4 and form_of is null), 107,
  'and every Generation IV species');
select is((select count(*)::int from public.pokedex_species where generation = 5 and form_of is null), 156,
  'and every Generation V species');
select is((select count(*)::int from public.pokedex_species where generation = 6 and form_of is null), 72,
  'and every Generation VI species');
select is((select count(*)::int from public.pokedex_species where generation = 7 and form_of is null), 88,
  'and every Generation VII species');
select is((select count(*)::int from public.pokedex_species where generation = 8 and form_of is null), 96,
  'and every Generation VIII species, Legends: Arceus''s too');
select is((select count(*)::int from public.pokedex_species where generation = 9 and form_of is null), 120,
  'and every Generation IX species');

select is((select count(*)::int from public.pokedex_species where form_of is not null), 460,
  'and every other form those games had, Mega Evolutions, Legends: Z-A''s too, Alolan, Galarian, Hisuian and Paldean forms and Gigantamax, but Arceus''s ??? type');
select is_empty(
  $$ select slug from public.pokedex_species
      where slug ~ '(totem|starter|battle-bond|power-construct|-(orange|yellow|green|blue|indigo|violet)-meteor)$'
         or slug in ('mothim-sandy', 'scatterbug-polar', 'pikachu-cosplay', 'pichu-spiky-eared', 'greninja-ash',
                     'eternatus-eternamax', 'sinistea-antique', 'poltchageist-artisan')
         or slug ~ '^(koraidon|miraidon)-' and slug not in ('koraidon-apex-build', 'miraidon-ultimate-mode') $$,
  'but no Totem, Partner, one game''s form, other ability, Minior shell but one, Mothim cloak, look alike, one battle''s form or ride');
select is(
  (select count(*)::int from public.pokedex_species
    where evolution_method like 'mega-evolution-holding-%'
      and evolution_method not in (select 'mega-evolution-holding-' || id from public.pokedex_items
                                    where sprite like '/sprites/%')),
  49, 'Legends: Z-A''s and Mega Dimension''s 49 Mega Evolutions are in, each on a drawn stone');
select set_eq(
  $$ select slug from public.pokedex_species
      where slug in ('polteageist-antique', 'sinistcha-masterpiece') and evolves_from_id is null $$,
  array['polteageist-antique', 'sinistcha-masterpiece'],
  'Antique Polteageist and Masterpiece Sinistcha are looks that evolve from nothing, so no egg or evolution gives one');
select is_empty(
  $$ select slug from public.pokedex_species where slug like 'pikachu-%-cap' $$,
  'and no Pikachu in a cap, an event gift in a costume');

select is((select count(*)::int from public.pokedex_entries where dex = 'national' and is_default), 1025, 'the national pokedex lists them');
select is((select count(*)::int from public.pokedex_entries where dex = 'kanto' and is_default), 151, 'Kanto''s the first 151');
select is((select count(*)::int from public.pokedex_entries where dex = 'johto' and is_default), 251, 'Johto''s the first 251, in its own order');
select is((select number from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
            where e.dex = 'johto' and s.slug = 'pikachu'), 22::smallint, 'Pikachu is Johto''s No.22');
select is((select count(*)::int from public.pokedex_entries where dex = 'hoenn' and is_default), 202,
  'and Hoenn''s 202, from Generation III and before');
select is((select count(*)::int from public.pokedex_entries where dex = 'sinnoh' and is_default), 217,
  'and Platinum''s 210, from Generation IV and before, with the 7 legendaries and mythicals it leaves out after them');
select is((select number from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
            where e.dex = 'sinnoh' and s.slug = 'arceus-normal'), 217::smallint, 'Arceus is Sinnoh''s last, No.217');
select is((select count(*)::int from public.pokedex_entries where dex = 'unova' and is_default), 301,
  'and Black 2 and White 2''s 301, from Generation V and before');
select is((select number from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
            where e.dex = 'unova' and s.slug = 'victini'), 0::smallint, 'Victini is Unova''s No.0');
select is((select count(*)::int from public.pokedex_entries where dex = 'kalos' and is_default), 457,
  'and X and Y''s 454, Central, Coastal and Mountain together, with the 3 mythicals they leave out after them');
select is(
  (select string_agg(s.slug || ':' || e.number, ' ' order by e.number)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'kalos' and e.is_default and e.number in (1, 151, 304, 454, 457)),
  'chespin:1 drifloon:151 diglett:304 mewtwo:454 volcanion:457',
  'Coastal numbers on from Central, and Mountain from Coastal');
select is((select count(*)::int from public.pokedex_entries where dex = 'alola' and is_default), 405,
  'and Ultra Sun and Ultra Moon''s 403, with Meltan and Melmetal after them');
select is(
  (select string_agg(s.slug || ':' || e.number, ' ' order by e.number)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'alola' and e.is_default and e.number in (1, 403, 404, 405)),
  'rowlet:1 zeraora:403 meltan:404 melmetal:405',
  'Meltan and Melmetal come after Zeraora');
select is(
  (select string_agg(s.slug || ':' || e.number, ' ' order by e.number)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'galar' and e.is_default and e.number in (1, 400, 401, 584)),
  'grookey:1 eternatus:400 slowpoke-galar:401 calyrex:584',
  'Galar''s 400, then those the Isle of Armor and the Crown Tundra add, each once');
select is(
  (select string_agg(e.dex || ':' || s.slug, ' ' order by e.dex, s.id)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.is_default and s.slug in ('raichu', 'raichu-alola', 'qwilfish', 'qwilfish-hisui',
      'darmanitan-galar-standard', 'darmanitan-galar-zen', 'tauros-paldea-combat-breed',
      'tauros-paldea-blaze-breed')
      and e.dex in ('kanto', 'alola', 'galar', 'hisui', 'paldea')),
  'alola:raichu-alola galar:raichu galar:qwilfish galar:darmanitan-galar-standard hisui:raichu hisui:qwilfish-hisui kanto:raichu paldea:raichu paldea:qwilfish paldea:tauros-paldea-combat-breed',
  'a pokedex lists its region''s form where there is one, the first of several');
select is((select count(*)::int from public.pokedex_entries where dex = 'hisui' and is_default), 242,
  'and Legends: Arceus''s 242');
select is(
  (select string_agg(s.slug || ':' || e.number, ' ' order by e.number)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'hisui' and e.is_default and e.number in (1, 50, 234, 242)),
  'rowlet:1 wyrdeer:50 enamorus-incarnate:234 darkrai:242',
  'from Rowlet to Darkrai, Hisui''s own species among them');
select is(
  (select string_agg(s.slug || ':' || e.number, ' ' order by e.number)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'paldea' and e.is_default and e.number in (1, 400, 401, 499, 664)),
  'sprigatito:1 miraidon-ultimate-mode:400 spinarak:401 ogerpon:499 pecharunt:664',
  'Paldea''s 400, then those Kitakami and Blueberry add, each once');
select is(
  (select string_agg(s.slug || ':' || e.number, ' ' order by e.number)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'lumiose' and e.is_default and e.number in (1, 232, 233, 364)),
  'chikorita:1 mewtwo:232 mankey:233 zeraora:364',
  'Lumiose''s 232, then Hyperspace Lumiose''s 132 numbered on');
select is(
  (select string_agg(s.slug, ' ' order by s.id)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'lumiose' and e.number = 54),
  'raichu raichu-alola raichu-mega-x raichu-mega-y',
  'and a number lists its Megas with its other forms');
select is(
  (select count(*)::int from public.pokedex_species s
    where s.form_of is null
      and not exists (select 1 from public.pokedex_entries e
                       where e.species_id = s.id
                         and (e.dex = (array['kanto', 'johto', 'hoenn', 'sinnoh', 'unova', 'kalos', 'alola', 'galar',
                                             'paldea'])[s.generation]
                              or e.dex = 'hisui' and s.generation = 8))),
  0, 'every species is in its own generation''s regional pokedex, Generation VIII''s in Galar''s or Hisui''s');

select isnt(
  (select ko_description from public.pokedex_entries where dex = 'national' and number = 6 and is_default),
  (select ko_description from public.pokedex_entries where dex = 'kanto' and number = 6 and is_default),
  'each pokedex writes its own entry');

select is(
  (select row(f.slug, m.trigger, m.level, m.item)::text
     from public.pokedex_species s
     join public.pokedex_species f on f.id = s.evolves_from_id
     join public.pokedex_evolution_methods m on m.id = s.evolution_method
    where s.slug = 'raichu'),
  '(pikachu,use-item,,thunder-stone)',
  'an evolution names the row it comes from, and a method: what sets it off, and what it takes');

select is(
  (select i.ko_name from public.pokedex_evolution_methods m join public.pokedex_items i on i.id = m.item
    where m.id = 'use-item-thunder-stone'),
  '천둥의돌', 'and the item is named');

select is((select evolution_method from public.pokedex_species where slug = 'charmeleon'), 'level-up-16',
  'a method is named for what it is, so every Lv.16 evolution shares one');

select is_empty(
  $$ select slug from public.pokedex_species
      where ko_name is null or en_name is null or ko_genus is null or en_genus is null $$,
  'every form is named and categorised in Korean and English, though a language may be missing');

select is(public.pokedex_first_form(149), 147, 'Dragonite''s family starts with Dratini');
select is(public.pokedex_first_form(26), 172, 'and Raichu''s with Pichu, from the generation after');

select is(
  (select row(f.slug, m.trigger, m.level, m.held_item, m.min_happiness, m.time_of_day, m.relative_physical_stats)::text
     from public.pokedex_species s
     join public.pokedex_species f on f.id = s.evolves_from_id
     join public.pokedex_evolution_methods m on m.id = s.evolution_method
    where s.slug = 'hitmonchan'),
  '(tyrogue,level-up,20,,,,-1)',
  'a method keeps what Generation II adds: Attack against Defense');
select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s where s.slug in ('steelix', 'umbreon', 'crobat')),
  'crobat:level-up-happiness-160 umbreon:level-up-happiness-160-night steelix:trade-holding-metal-coat',
  'an item held in a trade, friendship, and the time of day');

select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s where s.slug in ('silcoon', 'cascoon', 'milotic', 'shedinja')),
  'silcoon:level-up-7-chance-50 cascoon:level-up-7-chance-50 shedinja:shed milotic:level-up-beauty-170',
  'a method keeps what Generation III adds: a share by personality, beauty, and shedding');
select is(public.pokedex_first_form(184), 298, 'Azumarill''s family starts with Azurill, from Generation III');

select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s
    where s.slug in ('gallade', 'mothim-plant', 'ambipom', 'magnezone', 'mantine', 'wormadam-plant')),
  'mantine:level-up-with-remoraid wormadam-plant:level-up-20-female mothim-plant:level-up-20-male'
    || ' ambipom:level-up-knowing-double-hit magnezone:level-up-at-mt-coronet gallade:use-item-dawn-stone-male',
  'a method keeps what Generation IV adds: a gender, a move, a place, and a party');
select is((select evolves_from_id from public.pokedex_species where slug = 'manaphy'), null,
  'Phione shares Manaphy''s chain, but never becomes it');
select is(public.pokedex_first_form(143), 446, 'Snorlax''s family starts with Munchlax, from Generation IV');
select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s where s.slug in ('escavalier', 'accelgor')),
  'escavalier:trade-for-shelmet accelgor:trade-for-karrablast',
  'a method keeps what Generation V adds: trading for a given species');
select is(
  (select string_agg(s.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s where s.slug in ('pangoro', 'malamar', 'sylveon', 'goodra')),
  'pangoro:level-up-32-with-dark-type malamar:level-up-30-upside-down'
    || ' sylveon:level-up-knowing-fairy-move-affection-2 goodra:level-up-50-in-rain',
  'a method keeps what Generation VI adds: a type in the party, a move''s type, affection, rain and upside down');
select is(
  (select string_agg(s.slug || ':' || coalesce(f.slug, '-') || ':' || coalesce(s.evolution_method, '-'), ' ' order by s.id)
     from public.pokedex_species s left join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('meowstic-male', 'meowstic-female', 'vivillon-meadow', 'vivillon-polar')),
  'vivillon-meadow:spewpa-icy-snow:level-up-12 meowstic-male:espurr:level-up-25-male'
    || ' vivillon-polar:-:- meowstic-female:espurr:level-up-25-female',
  'a female Espurr becomes a female Meowstic, and Spewpa the default Vivillon alone');
select is(
  (select string_agg(s.slug || ':' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('charizard-mega-x', 'kyogre-primal', 'rayquaza-mega')),
  'charizard-mega-x:charizard:mega-evolution-holding-charizardite-x'
    || ' kyogre-primal:kyogre:primal-reversion-holding-blue-orb'
    || ' rayquaza-mega:rayquaza:mega-evolution-knowing-dragon-ascent',
  'a Mega Evolution or Primal Reversion is a stage after its default form, on what it holds or knows');
select is(
  (select string_agg(s.slug || ':' || f.slug || ':' || s.ko_form_name, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('dragonite-mega', 'floette-mega', 'zygarde-mega', 'absol-mega-z', 'raichu-mega-y',
                     'meowstic-female-mega', 'tatsugiri-droopy-mega', 'magearna-original-mega')),
  'dragonite-mega:dragonite:메가망나뇽 floette-mega:floette-eternal:메가플라엣테'
    || ' zygarde-mega:zygarde-complete:메가지가르데 raichu-mega-y:raichu:메가라이츄Y'
    || ' absol-mega-z:absol:메가앱솔Z magearna-original-mega:magearna-original:메가마기아나 500년 전의 색'
    || ' tatsugiri-droopy-mega:tatsugiri-droopy:메가싸리용 늘어진 모습'
    || ' meowstic-female-mega:meowstic-female:메가냐오닉스 암컷',
  'a Legends: Z-A Mega comes after the form that holds its stone, and is named in Korean');
select is(
  (select string_agg(id || ':' || ko_name, ' ' order by id) from public.pokedex_items
    where id in ('floettite', 'magearnite')),
  'floettite:플라엣테나이트 magearnite:마기아나이트',
  'and its stone is named as the games name it, the Floettite for Floette');
select is(
  (select string_agg(s.slug || ':' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('solgaleo', 'lunala', 'melmetal', 'lycanroc-dusk', 'necrozma-ultra')),
  'solgaleo:cosmoem:level-up-53-in-sun lunala:cosmoem:level-up-53-in-moon melmetal:meltan:meltan-candies'
    || ' lycanroc-dusk:rockruff-own-tempo:level-up-25-dusk'
    || ' necrozma-ultra:necrozma:ultra-burst-holding-ultranecrozium-z',
  'a method keeps what Generation VII adds: a game, dusk, Pokémon GO, and Ultra Burst as a stage');
select is(
  (select string_agg(s.slug || ':' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('raichu', 'raichu-alola', 'raticate-alola', 'marowak-alola', 'sandslash-alola')),
  'raichu:pikachu:use-item-thunder-stone raticate-alola:rattata-alola:level-up-20-night'
    || ' raichu-alola:pikachu:use-item-thunder-stone-in-alola'
    || ' sandslash-alola:sandshrew-alola:use-item-ice-stone'
    || ' marowak-alola:cubone:level-up-28-night-in-alola',
  'an Alolan form comes from its own, or only in Alola from the default');
select is(
  (select string_agg(s.slug || ':' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('toxtricity-amped', 'runerigus', 'alcremie-vanilla-cream-strawberry-sweet',
                     'sirfetchd', 'urshifu-rapid-strike')),
  'toxtricity-amped:toxel:level-up-30-adamant-or-12-more-natures'
    || ' sirfetchd:farfetchd-galar:three-critical-hits'
    || ' runerigus:yamask-galar:take-damage-at-dusty-bowl-after-49-damage'
    || ' alcremie-vanilla-cream-strawberry-sweet:milcery:spin-holding-strawberry-sweet-day'
    || ' urshifu-rapid-strike:kubfu:tower-of-waters',
  'a method keeps what Generation VIII adds: a nature, damage taken, a spin and a tower');
select is(
  (select string_agg(s.slug || ':' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('perrserker', 'mr-rime', 'weezing-galar', 'slowbro-galar')),
  'perrserker:meowth-galar:level-up-28 mr-rime:mr-mime-galar:level-up-42'
    || ' slowbro-galar:slowpoke-galar:use-item-galarica-cuff weezing-galar:koffing:level-up-35-in-galar',
  'a species reached only from a Galarian form comes from it, and a Galarian form from its own or only in Galar');
select is(
  (select string_agg(slug || ':' || ko_form_name, ' ' order by id)
     from public.pokedex_species
    where slug in ('charizard-gmax', 'alcremie-matcha-cream-love-sweet', 'urshifu-rapid-strike-gmax')),
  'charizard-gmax:거다이맥스 urshifu-rapid-strike-gmax:연격의 태세 거다이맥스 alcremie-matcha-cream-love-sweet:밀키말차 하트',
  'Gigantamax is a look, and each Alcremie is named for its cream and its sweet');
select is(
  (select string_agg(s.slug || ':' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('wyrdeer', 'ursaluna', 'basculegion-female', 'overqwil', 'typhlosion-hisui',
                     'arcanine-hisui', 'goodra-hisui')),
  'wyrdeer:stantler:agile-style-move-using-psyshield-bash-20-times'
    || ' ursaluna:ursaring:use-item-peat-block-full-moon'
    || ' overqwil:qwilfish-hisui:level-up-knowing-barb-barrage'
    || ' arcanine-hisui:growlithe-hisui:use-item-fire-stone'
    || ' typhlosion-hisui:quilava:level-up-36-in-hisui'
    || ' goodra-hisui:sliggoo-hisui:level-up-50-in-rain'
    || ' basculegion-female:basculin-white-striped:recoil-damage-female-after-294-damage',
  'a method keeps what Legends: Arceus adds, a move used in a style and a full moon, but Overqwil''s as Scarlet and Violet have it');
select is(
  (select string_agg(slug || ':' || ko_form_name, ' ' order by id)
     from public.pokedex_species
    where slug in ('growlithe-hisui', 'dialga-origin', 'basculin-white-striped', 'enamorus-therian')),
  'growlithe-hisui:히스이의 모습 dialga-origin:오리진폼 basculin-white-striped:백색근의 모습 enamorus-therian:영물폼',
  'Hisuian forms, Origin Dialga, White-Striped Basculin and Therian Enamorus are looks');
select is(
  (select string_agg(s.slug || ':' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('pawmot', 'palafin-zero', 'annihilape', 'clodsire', 'kingambit', 'gholdengo',
                     'maushold-family-of-three', 'sinistcha-unremarkable')),
  'pawmot:pawmo:level-up-after-1000-steps palafin-zero:finizen:level-up-38-in-union-circle'
    || ' annihilape:primeape:use-move-using-rage-fist-20-times clodsire:wooper-paldea:level-up-20'
    || ' kingambit:bisharp:three-defeated-bisharp gholdengo:gimmighoul-chest:gimmighoul-coins'
    || ' sinistcha-unremarkable:poltchageist-counterfeit:use-item-unremarkable-teacup'
    || ' maushold-family-of-three:tandemaus:in-battle-level-up-25-chance-1',
  'a method keeps what Generation IX adds: steps, a Union Circle, a move used, and Paldean Wooper''s own');
select is(
  (select string_agg(slug || ':' || ko_form_name || ':' || (evolves_from_id is not null), ' ' order by id)
     from public.pokedex_species
    where slug in ('tauros-paldea-aqua-breed', 'wooper-paldea', 'palafin-hero', 'ursaluna-bloodmoon',
                   'gimmighoul-roaming', 'terapagos-stellar')),
  'tauros-paldea-aqua-breed:팔데아의 모습 워터종:false wooper-paldea:팔데아의 모습:false'
    || ' palafin-hero:마이티폼:false gimmighoul-roaming:도보폼:false'
    || ' ursaluna-bloodmoon:붉은 달:false terapagos-stellar:스텔라폼:false',
  'Paldean forms, Hero Palafin, Roaming Gimmighoul, Bloodmoon Ursaluna and Stellar Terapagos are looks');

select is(
  (select string_agg(s.slug || ':' || e.is_default, ' ' order by s.id)
     from public.pokedex_entries e join public.pokedex_species s on s.id = e.species_id
    where e.dex = 'national' and e.number = 479),
  'rotom:true rotom-heat:false rotom-wash:false rotom-frost:false rotom-fan:false rotom-mow:false',
  'a number lists every form of its species, and shows the default');
select is(
  (select row(ko_name, ko_form_name, en_form_name, form_of, type1, type2)::text
     from public.pokedex_species where slug = 'rotom-heat'),
  '(로토무,히트로토무,"Heat Rotom",479,electric,fire)',
  'a form keeps its species'' name, has one of its own, and its own types');
select is(
  (select row(ko_form_name, form_of, type1)::text from public.pokedex_species where slug = 'arceus-fire'),
  '(불꽃타입,493,fire)',
  'and is named in Korean where PokéAPI names it only in English');
select is(
  (select string_agg(slug || ':' || coalesce(ko_form_name, '-'), ' ' order by id)
     from public.pokedex_species where slug in ('pikachu', 'pichu', 'unown-a', 'unown-question')),
  'pikachu:- pichu:- unown-a:A unown-question:?',
  'a species with one form names none, and neither does a default form the games leave unnamed');
select is(
  (select string_agg(s.slug || '<' || f.slug || ':' || s.evolution_method, ' ' order by s.id)
     from public.pokedex_species s join public.pokedex_species f on f.id = s.evolves_from_id
    where s.slug in ('gastrodon-east', 'wormadam-sandy', 'gastrodon-west')),
  'gastrodon-west<shellos-west:level-up-30 wormadam-sandy<burmy-sandy:level-up-20-female gastrodon-east<shellos-east:level-up-30',
  'a form evolves from the form of the same name');
select is(
  (select count(*)::int from public.pokedex_species
    where slug in ('cherrim-sunshine', 'rotom-heat') and evolves_from_id is not null),
  0, 'and from nothing where the form before has no such form');

select is(
  (select string_agg(slug || ':' || (sprites ? 'front_female'), ' ' order by id)
     from public.pokedex_species where slug in ('pikachu', 'nidoran-f', 'combee')),
  'pikachu:true nidoran-f:false combee:true',
  'a female that looks different has a sprite of her own');

select is(
  (select string_agg(s.slug || ':' || s.evolution_method || '>' || l.evolution_method, ' ' order by s.id)
     from public.pokedex_latest_evolutions l join public.pokedex_species s on s.id = l.species_id
    where s.slug in ('magnezone', 'leafeon', 'sylveon', 'overqwil', 'milotic')),
  'milotic:level-up-beauty-170>trade-holding-prism-scale'
    || ' magnezone:level-up-at-mt-coronet>use-item-thunder-stone'
    || ' leafeon:level-up-at-eterna-forest>use-item-leaf-stone'
    || ' sylveon:level-up-knowing-fairy-move-affection-2>level-up-happiness-160-knowing-fairy-move'
    || ' overqwil:level-up-knowing-barb-barrage>use-move-using-barb-barrage-20-times',
  'the newest games'' way stands beside the oldest''s, where the two differ');
select is((select count(*)::int from public.pokedex_latest_evolutions l
             join public.pokedex_species s on s.id = l.species_id
            where l.evolution_method = s.evolution_method), 0,
  'a form whose newest way is its oldest has no row');

select is((select category from public.pokedex_species where slug = 'mewtwo'), 'legendary', 'a category is one of three, or none');

set local role anon;
select throws_ok($$ update public.pokedex_species set capture_rate = 255 $$, '42501', null,
  'anyone may read it, and nobody may change it');
select throws_ok($$ select * from public.coder_egg_species $$, '42501', null,
  'the game''s own tables stay closed to visitors');
reset role;

select * from finish();
rollback;
