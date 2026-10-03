// Reads PokéAPI once and writes what the rest of the repository needs from it:
// the sprite manifest this app serves from, and the migration that fills the
// pokedex_ tables. Both are committed; nothing reads PokéAPI at build or run
// time.
//
//   node scripts/generate.ts
//
// Run it again only to change what is included. The sprite commit is pinned
// below, so the manifest's hashes stay true until someone moves it.
//
// A migration that has been applied never changes, so each run that changes
// what is included writes a new one, named in MIGRATION below, and leaves the
// earlier ones alone. It upserts only the rows that differ from what the
// earlier ones wrote, a changed row as well as a new one: a later generation
// reaches back into an earlier one, as Pichu does into Pikachu's row.

import { createHash } from 'node:crypto'
import { readdir, readFile, writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

/** PokeAPI/sprites at the commit every hash in the manifest was taken from. */
const SPRITES_COMMIT = 'a13b1f4ccd77f35fd1370d2db5f0051221e9683f'
const SPRITES_BASE = `https://raw.githubusercontent.com/PokeAPI/sprites/${SPRITES_COMMIT}/sprites/pokemon`
const ITEMS_BASE = `https://raw.githubusercontent.com/PokeAPI/sprites/${SPRITES_COMMIT}/sprites/items`

/**
 * What the generated files say about where their contents come from. PokéAPI's
 * BSD licence asks for its notice to travel with the data; the sprites
 * repository is CC0, but that waives only its own rights, not those in the
 * images.
 */
const POKEAPI_NOTICE =
  'Data from PokéAPI, © 2013–2023 Paul Hallett and PokéAPI contributors, BSD 3-Clause.'
const SPRITES_NOTICE =
  'Sprites from PokeAPI/sprites (CC0 1.0); the images are © The Pokémon Company.'

/**
 * Generations I to IX as far as Scarlet and Violet and their two DLC: national
 * dex numbers 1 to 1025, in every form those games had. A form a later game
 * added waits for its generation.
 */
const LAST_DEX_NO = 1025
const LAST_GENERATION = 9

/**
 * Games of a kept generation whose forms wait. Legends: Z-A is Generation
 * IX's, but its Mega Evolutions, Mega Dimension's too, come in apart from
 * Paldea's, as Hisui's forms came in apart from Galar's.
 */
const LATER_VERSION_GROUPS = new Set(['legends-za', 'mega-dimension'])

/**
 * The generation of a region PokéAPI gives none. Hisui is Legends: Arceus's,
 * a Generation VIII game.
 */
const REGION_GENERATIONS: Record<string, number> = { hisui: 8 }

/**
 * Forms left out though their generation is in. Arceus's ??? type has no
 * plate to hold, so no game shows it, and no type row to point at. PokéAPI
 * makes Frillish's, Jellicent's and Pyroar's females forms, where a female
 * who looks different is her species' default form with sprites of her own,
 * as Pikachu's is; left out, they are. Female Meowstic, with moves of her
 * own, stays a form. Cosplay Pikachu is only Omega Ruby's and Alpha
 * Sapphire's, and never leaves them; so are Totem Pokémon only Sun and Moon's
 * and Ultra Sun and Ultra Moon's, and Partner Pikachu and Eevee only Let's
 * Go's. Spiky-eared Pichu came to one event in HeartGold and SoulSilver and
 * could never leave them. Battle Bond Greninja and Power Construct Zygarde
 * are Greninja and Zygarde with another ability, and look the same; Complete
 * Zygarde, which Zygarde becomes, stays, as later games have it too, but
 * Ash-Greninja is only Sun and Moon's and Ultra Sun and Ultra Moon's. So is
 * Gigantamax only Sword and Shield's; its forms, whose names all end in
 * -gmax, are left out by that rather than listed here. Minior's shell is the same whatever its
 * core, so one Meteor Form stands for the seven, beside the seven cores.
 * Eternamax Eternatus is met in one battle and never caught. An Antique Form
 * Sinistea or Polteageist is a Phony one with a mark under its pot, and
 * Pokémon HOME shows the two alike; so is an Artisan Poltchageist or a
 * Masterpiece Sinistcha a Counterfeit or an Unremarkable one. Koraidon's builds
 * and Miraidon's modes are how it is ridden in Scarlet and Violet: it battles
 * and goes to HOME in one, its own.
 */
const LEFT_OUT_FORMS = new Set([
  'arceus-unknown',
  'pichu-spiky-eared',
  'frillish-female',
  'jellicent-female',
  'pyroar-female',
  'pikachu-rock-star',
  'pikachu-belle',
  'pikachu-pop-star',
  'pikachu-phd',
  'pikachu-libre',
  'pikachu-cosplay',
  'pikachu-starter',
  'eevee-starter',
  'raticate-totem-alola',
  'marowak-totem',
  'gumshoos-totem',
  'vikavolt-totem',
  'ribombee-totem',
  'araquanid-totem',
  'lurantis-totem',
  'salazzle-totem',
  'togedemaru-totem',
  'mimikyu-totem-disguised',
  'mimikyu-totem-busted',
  'kommo-o-totem',
  'greninja-battle-bond',
  'greninja-ash',
  'zygarde-10-power-construct',
  'zygarde-50-power-construct',
  'minior-orange-meteor',
  'minior-yellow-meteor',
  'minior-green-meteor',
  'minior-blue-meteor',
  'minior-indigo-meteor',
  'minior-violet-meteor',
  'eternatus-eternamax',
  'sinistea-antique',
  'polteageist-antique',
  'poltchageist-artisan',
  'sinistcha-masterpiece',
  'koraidon-limited-build',
  'koraidon-sprinting-build',
  'koraidon-swimming-build',
  'koraidon-gliding-build',
  'miraidon-low-power-mode',
  'miraidon-drive-mode',
  'miraidon-aquatic-mode',
  'miraidon-glide-mode',
])

/**
 * Species whose forms are all left out but the default. PokéAPI gives
 * Scatterbug and Spewpa each of Vivillon's patterns, which no game shows
 * until one becomes a Vivillon; the pattern is where it evolves. It gives
 * Mothim Burmy's cloaks, though a Mothim looks the same from any.
 */
const ONE_FORM_ONLY = new Set(['scatterbug', 'spewpa', 'mothim'])

/**
 * Species whose default form alone comes from the form before, as Mothim
 * comes only from Plant Cloak Burmy: every Vivillon pattern comes from
 * Spewpa, and twenty in a row would bury the rest of the family. So with
 * Alcremie's 63 creams and sweets from Milcery.
 */
const ONLY_DEFAULT_EVOLVES = new Set(['vivillon', 'alcremie'])

/**
 * Forms no game lets be shiny, so Pokémon HOME has no shiny render of them:
 * their shiny is their plain look. Pikachu in a cap came to events only,
 * never shiny.
 */
const NEVER_SHINY = new Set([
  'pikachu-original-cap',
  'pikachu-hoenn-cap',
  'pikachu-sinnoh-cap',
  'pikachu-unova-cap',
  'pikachu-kalos-cap',
  'pikachu-alola-cap',
  'pikachu-partner-cap',
  'pikachu-world-cap',
])

/** PokéAPI names these forms in English only. */
const FORM_KO_NAMES: Record<string, string> = {
  'arceus-normal': '노말타입',
  'arceus-fighting': '격투타입',
  'arceus-flying': '비행타입',
  'arceus-poison': '독타입',
  'arceus-ground': '땅타입',
  'arceus-rock': '바위타입',
  'arceus-bug': '벌레타입',
  'arceus-ghost': '고스트타입',
  'arceus-steel': '강철타입',
  'arceus-fire': '불꽃타입',
  'arceus-water': '물타입',
  'arceus-grass': '풀타입',
  'arceus-electric': '전기타입',
  'arceus-psychic': '에스퍼타입',
  'arceus-ice': '얼음타입',
  'arceus-dragon': '드래곤타입',
  'arceus-dark': '악타입',
  'arceus-fairy': '페어리타입',
  'rockruff-own-tempo': '마이페이스',
  'dialga-origin': '오리진폼',
  'palkia-origin': '오리진폼',
  'basculin-white-striped': '백색근의 모습',
  'basculegion-male': '수컷의 모습',
  'basculegion-female': '암컷의 모습',
  'enamorus-incarnate': '화신폼',
  'enamorus-therian': '영물폼',
  'tauros-paldea-combat-breed': '팔데아의 모습 컴뱃종',
  'tauros-paldea-blaze-breed': '팔데아의 모습 블레이즈종',
  'tauros-paldea-aqua-breed': '팔데아의 모습 워터종',
  'wooper-paldea': '팔데아의 모습',
  'oinkologne-male': '수컷의 모습',
  'oinkologne-female': '암컷의 모습',
  'maushold-family-of-four': '네 식구',
  'maushold-family-of-three': '세 식구',
  'squawkabilly-green-plumage': '그린 페더',
  'squawkabilly-blue-plumage': '블루 페더',
  'squawkabilly-yellow-plumage': '옐로 페더',
  'squawkabilly-white-plumage': '화이트 페더',
  'palafin-zero': '나이브폼',
  'palafin-hero': '마이티폼',
  'tatsugiri-curly': '젖힌 모습',
  'tatsugiri-droopy': '늘어진 모습',
  'tatsugiri-stretchy': '뻗은 모습',
  'dudunsparce-two-segment': '두 마디폼',
  'dudunsparce-three-segment': '세 마디폼',
  'gimmighoul-chest': '상자폼',
  'gimmighoul-roaming': '도보폼',
  terapagos: '노말폼',
  'terapagos-terastal': '테라스탈폼',
  'terapagos-stellar': '스텔라폼',
  ...alcremieKoNames(),
}

/**
 * Alcremie's 63 looks, a cream and a sweet each. PokéAPI names in Korean only
 * the cream, and only with the Strawberry Sweet, so each takes its cream's
 * name and its sweet's, as the sweet's item is named less 사탕공예.
 */
function alcremieKoNames(): Record<string, string> {
  const creams: Record<string, string> = {
    'vanilla-cream': '밀키바닐라',
    'ruby-cream': '밀키루비',
    'matcha-cream': '밀키말차',
    'mint-cream': '밀키민트',
    'lemon-cream': '밀키레몬',
    'salted-cream': '밀키솔트',
    'ruby-swirl': '루비믹스',
    'caramel-swirl': '캐러멜믹스',
    'rainbow-swirl': '트리플믹스',
  }
  const sweets: Record<string, string> = {
    strawberry: '딸기',
    berry: '베리',
    love: '하트',
    star: '스타',
    clover: '네잎',
    flower: '꽃',
    ribbon: '리본',
  }
  return Object.fromEntries(
    Object.entries(creams).flatMap(([cream, creamKo]) =>
      Object.entries(sweets).map(([sweet, sweetKo]) => [
        `alcremie-${cream}-${sweet}-sweet`,
        `${creamKo} ${sweetKo}`,
      ]),
    ),
  )
}

/** A Hisuian form, as the games name it in Korean; PokéAPI names it in English only. */
const HISUIAN_KO = '히스이의 모습'

/** The languages kept, Korean and English for now, as PokéAPI codes them. */
const LANGUAGES = ['ko', 'en']

/**
 * The pokedexes kept, with the names PokéAPI lacks in Korean, and which game's
 * entry each prefers, first found wins; with none of them, the newest entry.
 */
const POKEDEXES: Record<
  string,
  {
    apiId: number | number[]
    names: Record<string, string>
    versions: string[]
    appended?: number[]
  }
> = {
  national: { apiId: 1, names: { ko: '전국도감', en: 'National Pokédex' }, versions: [] },
  kanto: {
    apiId: 2,
    names: { ko: '관동도감', en: 'Kanto Pokédex' },
    versions: ['lets-go-pikachu', 'lets-go-eevee', 'firered', 'leafgreen', 'yellow', 'red', 'blue'],
  },
  // Gold, Silver and Crystal's, not HeartGold and SoulSilver's, which lists
  // Generation IV species too. None of these games has Korean entries in
  // PokéAPI, so Korean falls back to the newest.
  johto: {
    apiId: 3,
    names: { ko: '성도도감', en: 'Johto Pokédex' },
    versions: ['heartgold', 'soulsilver', 'crystal', 'gold', 'silver'],
  },
  // Ruby, Sapphire and Emerald's, not Omega Ruby and Alpha Sapphire's, which
  // lists Generation IV to VI species too.
  hoenn: {
    apiId: 4,
    names: { ko: '호연도감', en: 'Hoenn Pokédex' },
    versions: ['omega-ruby', 'alpha-sapphire', 'emerald', 'ruby', 'sapphire'],
  },
  // Platinum's, not Diamond and Pearl's, unlike the others, which are the
  // first games': those leave out 26 Generation IV species, Magnezone and
  // Togekiss among them, where Platinum leaves out 7. Those 7, all legendary
  // or mythical, are appended after its last number in national order, so
  // every Generation I to IV species is in its own region's pokedex.
  sinnoh: {
    apiId: 6,
    names: { ko: '신오도감', en: 'Sinnoh Pokédex' },
    versions: ['brilliant-diamond', 'shining-pearl', 'platinum', 'diamond', 'pearl'],
    // Heatran, Regigigas, Cresselia, Phione, Darkrai, Shaymin and Arceus.
    appended: [485, 486, 488, 489, 491, 492, 493],
  },
  // Black 2 and White 2's, not Black and White's, which lists Generation V's
  // species only, where every other region's lists some from before. It
  // lists every Generation V species, from Victini at No.0.
  unova: {
    apiId: 9,
    names: { ko: '하나도감', en: 'Unova Pokédex' },
    versions: ['black-2', 'white-2', 'black', 'white'],
  },
  // X and Y's, which the games split in three, Central, Coastal and Mountain,
  // each numbered from 1. One pokedex here numbers them on from each other,
  // 1 to 454, as one Kalos egg holds all three. PokéAPI adds Diancie, Hoopa
  // and Volcanion at Central's end, where no game lists them; they go after
  // Mountain's last instead, as Platinum's missing seven do.
  kalos: {
    apiId: [12, 13, 14],
    names: { ko: '칼로스도감', en: 'Kalos Pokédex' },
    versions: ['x', 'y', 'omega-ruby', 'alpha-sapphire'],
    appended: [719, 720, 721],
  },
  // Ultra Sun and Ultra Moon's, not Sun and Moon's, which leaves out the
  // five Ultra Sun and Ultra Moon added. It lists every Generation VII
  // species but Meltan and Melmetal, which come after it. They came to Let's
  // Go and Pokémon GO, not an Alolan game, and no official source, Pokémon
  // HOME included, gives them a generation; numbered after Zeraora, they are
  // taken as Generation VII's, and Alola's.
  alola: {
    apiId: 21,
    names: { ko: '알로라도감', en: 'Alola Pokédex' },
    versions: ['ultra-sun', 'ultra-moon', 'sun', 'moon'],
    appended: [808, 809],
  },
  // Sword and Shield's, with the Isle of Armor's and the Crown Tundra's after
  // it, numbered on as Kalos's three are, as one Galar egg holds all three.
  // The two add theirs to many Galar has already: one already listed keeps
  // its first number. Together they list every Generation VIII species.
  galar: {
    apiId: [27, 28, 29],
    names: { ko: '가라르도감', en: 'Galar Pokédex' },
    versions: ['sword', 'shield'],
  },
  // Legends: Arceus's, the one game in Hisui. It lists every species from
  // No.899 on, among older ones, as the other regions' do.
  hisui: {
    apiId: 30,
    names: { ko: '히스이도감', en: 'Hisui Pokédex' },
    versions: ['legends-arceus'],
  },
  // Scarlet and Violet's, with the Teal Mask's Kitakami and the Indigo Disk's
  // Blueberry after it, numbered on as Galar's three are, as one Paldea egg
  // holds all three. Together they list every Generation IX species.
  paldea: {
    apiId: [31, 32, 33],
    names: { ko: '팔데아도감', en: 'Paldea Pokédex' },
    versions: ['scarlet', 'violet'],
  },
}

const MANIFEST = fileURLToPath(new URL('../sprites.json', import.meta.url))
const MIGRATION = fileURLToPath(
  new URL('../../../supabase/migrations/20261003150001_pokedex_data.sql', import.meta.url),
)

type Named = { name: string; url: string }
type Localised = { language: Named }
type Species = {
  id: number
  name: string
  names: ({ name: string } & Localised)[]
  genera: ({ genus: string } & Localised)[]
  flavor_text_entries: ({ flavor_text: string; version: Named } & Localised)[]
  generation: Named
  capture_rate: number
  hatch_counter: number
  gender_rate: number
  is_baby: boolean
  is_legendary: boolean
  is_mythical: boolean
  has_gender_differences: boolean
  growth_rate: Named
  evolution_chain: { url: string }
  varieties: { is_default: boolean; pokemon: Named }[]
}
type Pokemon = {
  id: number
  name: string
  height: number
  weight: number
  types: { slot: number; type: Named }[]
  stats: { base_stat: number; stat: Named }[]
  forms: Named[]
}
/**
 * One form of a Pokémon. A form with types of its own, as Arceus's have, says
 * them; the rest take the Pokémon's.
 */
type Form = {
  id: number
  name: string
  form_name: string
  is_default: boolean
  version_group: Named
  form_names: ({ name: string } & Localised)[]
  types: { slot: number; type: Named }[]
}
type EvolutionDetail = {
  trigger: Named
  min_level: number | null
  item: Named | null
  held_item: Named | null
  min_happiness: number | null
  time_of_day: string
  relative_physical_stats: number | null
  min_beauty: number | null
  gender: number | null
  known_move: Named | null
  location: Named | null
  party_species: Named | null
  party_type: Named | null
  trade_species: Named | null
  known_move_type: Named | null
  min_affection: number | null
  needs_overworld_rain: boolean
  turn_upside_down: boolean
  condition_expression: {
    percentage_chance: number | null
    variables: Named[]
  } | null
  required_pokemon_form: Named | null
  evolved_pokemon_form: Named | null
  region: Named | null
} & Record<string, unknown>
type ChainLink = {
  species: Named
  evolution_details: EvolutionDetail[]
  evolves_to: ChainLink[]
}

async function get<T>(url: string): Promise<T> {
  const response = await fetch(url.startsWith('http') ? url : `https://pokeapi.co/api/v2/${url}`)
  if (!response.ok) throw new Error(`${url}: ${response.status}`)
  return (await response.json()) as T
}

function idOf(resource: Named | { url: string }): number {
  return Number(resource.url.replace(/\/$/, '').split('/').pop())
}

/** One value per kept language. */
function localise<T extends Localised>(
  entries: T[],
  value: (entry: T) => string,
  pick: (matching: T[]) => T | undefined = (matching) => matching[0],
): Record<string, string> {
  const out: Record<string, string> = {}
  for (const code of LANGUAGES) {
    const chosen = pick(entries.filter((e) => e.language.name === code))
    if (chosen) out[code] = value(chosen)
  }
  return out
}

/** PokéAPI keeps the games' line breaks and page breaks; a screen wants prose. */
function prose(text: string): string {
  return text
    .replace(/\u00ad\n/g, '')
    .replace(/[\n\f\r]+/g, ' ')
    .replace(/ {2,}/g, ' ')
    .trim()
}

/**
 * Mega Evolution and Primal Reversion, as a stage after the form they come
 * from rather than a look of it: what each holds, or for Rayquaza knows.
 * PokéAPI's chains leave them out, so they are listed here.
 */
const MEGA_EVOLUTIONS: Record<string, { trigger: string; item?: string; move?: string }> = {
  'venusaur-mega': { trigger: 'mega-evolution', item: 'venusaurite' },
  'charizard-mega-x': { trigger: 'mega-evolution', item: 'charizardite-x' },
  'charizard-mega-y': { trigger: 'mega-evolution', item: 'charizardite-y' },
  'blastoise-mega': { trigger: 'mega-evolution', item: 'blastoisinite' },
  'beedrill-mega': { trigger: 'mega-evolution', item: 'beedrillite' },
  'pidgeot-mega': { trigger: 'mega-evolution', item: 'pidgeotite' },
  'alakazam-mega': { trigger: 'mega-evolution', item: 'alakazite' },
  'slowbro-mega': { trigger: 'mega-evolution', item: 'slowbronite' },
  'gengar-mega': { trigger: 'mega-evolution', item: 'gengarite' },
  'kangaskhan-mega': { trigger: 'mega-evolution', item: 'kangaskhanite' },
  'pinsir-mega': { trigger: 'mega-evolution', item: 'pinsirite' },
  'gyarados-mega': { trigger: 'mega-evolution', item: 'gyaradosite' },
  'aerodactyl-mega': { trigger: 'mega-evolution', item: 'aerodactylite' },
  'mewtwo-mega-x': { trigger: 'mega-evolution', item: 'mewtwonite-x' },
  'mewtwo-mega-y': { trigger: 'mega-evolution', item: 'mewtwonite-y' },
  'ampharos-mega': { trigger: 'mega-evolution', item: 'ampharosite' },
  'steelix-mega': { trigger: 'mega-evolution', item: 'steelixite' },
  'scizor-mega': { trigger: 'mega-evolution', item: 'scizorite' },
  'heracross-mega': { trigger: 'mega-evolution', item: 'heracronite' },
  'houndoom-mega': { trigger: 'mega-evolution', item: 'houndoominite' },
  'tyranitar-mega': { trigger: 'mega-evolution', item: 'tyranitarite' },
  'sceptile-mega': { trigger: 'mega-evolution', item: 'sceptilite' },
  'blaziken-mega': { trigger: 'mega-evolution', item: 'blazikenite' },
  'swampert-mega': { trigger: 'mega-evolution', item: 'swampertite' },
  'gardevoir-mega': { trigger: 'mega-evolution', item: 'gardevoirite' },
  'sableye-mega': { trigger: 'mega-evolution', item: 'sablenite' },
  'mawile-mega': { trigger: 'mega-evolution', item: 'mawilite' },
  'aggron-mega': { trigger: 'mega-evolution', item: 'aggronite' },
  'medicham-mega': { trigger: 'mega-evolution', item: 'medichamite' },
  'manectric-mega': { trigger: 'mega-evolution', item: 'manectite' },
  'sharpedo-mega': { trigger: 'mega-evolution', item: 'sharpedonite' },
  'camerupt-mega': { trigger: 'mega-evolution', item: 'cameruptite' },
  'altaria-mega': { trigger: 'mega-evolution', item: 'altarianite' },
  'banette-mega': { trigger: 'mega-evolution', item: 'banettite' },
  'absol-mega': { trigger: 'mega-evolution', item: 'absolite' },
  'glalie-mega': { trigger: 'mega-evolution', item: 'glalitite' },
  'salamence-mega': { trigger: 'mega-evolution', item: 'salamencite' },
  'metagross-mega': { trigger: 'mega-evolution', item: 'metagrossite' },
  'latias-mega': { trigger: 'mega-evolution', item: 'latiasite' },
  'latios-mega': { trigger: 'mega-evolution', item: 'latiosite' },
  'kyogre-primal': { trigger: 'primal-reversion', item: 'blue-orb' },
  'groudon-primal': { trigger: 'primal-reversion', item: 'red-orb' },
  'rayquaza-mega': { trigger: 'mega-evolution', move: 'dragon-ascent' },
  'lopunny-mega': { trigger: 'mega-evolution', item: 'lopunnite' },
  'garchomp-mega': { trigger: 'mega-evolution', item: 'garchompite' },
  'lucario-mega': { trigger: 'mega-evolution', item: 'lucarionite' },
  'abomasnow-mega': { trigger: 'mega-evolution', item: 'abomasite' },
  'gallade-mega': { trigger: 'mega-evolution', item: 'galladite' },
  'audino-mega': { trigger: 'mega-evolution', item: 'audinite' },
  'diancie-mega': { trigger: 'mega-evolution', item: 'diancite' },
  // From Dusk Mane or Dawn Wings Necrozma in the games, but a stage comes
  // after one form, and those two are looks of Necrozma's: it comes after
  // Necrozma, as the Megas do.
  'necrozma-ultra': { trigger: 'ultra-burst', item: 'ultranecrozium-z' },
}

/** Triggers PokéAPI has no row for, which MEGA_EVOLUTIONS names. */
const TRIGGERS_NOT_IN_POKEAPI: Record<string, Record<string, string>> = {
  'mega-evolution': { ko: '메가진화', en: 'Mega Evolution' },
  'primal-reversion': { ko: '원시회귀', en: 'Primal Reversion' },
  'ultra-burst': { ko: '울트라버스트', en: 'Ultra Burst' },
}

/**
 * Items PokéAPI names nothing, and whose bag sprite is filed under another
 * name: Ultranecrozium Z's is its held one.
 */
const ITEMS_NOT_IN_POKEAPI: Record<string, { names: Record<string, string>; sprite: string }> = {
  'ultranecrozium-z': {
    names: { ko: '울트라네크로Z', en: 'Ultranecrozium Z' },
    sprite: 'ultranecrozium-z--held',
  },
}

/**
 * The game a form is reached in, where PokéAPI does not say: a Cosmoem
 * becomes Solgaleo in Sun and Ultra Sun, and Lunala in Moon and Ultra Moon,
 * and PokéAPI gives each the same level and nothing else.
 */
const VERSION_ONLY: Record<string, string> = { solgaleo: 'sun', lunala: 'moon' }

/**
 * Items no evolution here names, which the Coder game evolves with in place of
 * what it cannot ask for: a Linking Cord in place of a trade, as the games
 * since Legends: Arceus have it, a Prism Scale in place of Feebas's beauty, a
 * Damp Rock in place of Sliggoo's rain, and Meltan Candy in place of the
 * 400 Pokémon GO asks.
 */
const GAME_ITEMS = [
  'linking-cord',
  'prism-scale',
  'damp-rock',
  'meltan-candy',
  // In place of Galarian Farfetch'd's three critical hits, a Leek, which
  // PokéAPI files under Stick, its name before Generation VIII.
  'stick',
  // In place of Kubfu's towers, the scrolls that stand for them in Scarlet
  // and Violet.
  'scroll-of-darkness',
  'scroll-of-waters',
  // In place of the three Bisharp leading others that Bisharp must defeat, the
  // Leader's Crest they hold; in place of Gimmighoul's 999 coins, one coin.
  'leaders-crest',
  'gimmighoul-coin',
]

/**
 * Items PokeAPI/sprites has no bag sprite for, even on master: PokeGosu draws
 * its own, in the same 30px style, with scripts/draw-items.ts.
 */
const DRAWN_ITEMS = new Set([
  'linking-cord',
  'meltan-candy',
  'tart-apple',
  'sweet-apple',
  'cracked-pot',
  'galarica-cuff',
  'galarica-wreath',
  'strawberry-sweet',
  'scroll-of-darkness',
  'scroll-of-waters',
  'black-augurite',
  'peat-block',
  'syrupy-apple',
  'metal-alloy',
  'auspicious-armor',
  'malicious-armor',
  'unremarkable-teacup',
  'leaders-crest',
  'gimmighoul-coin',
])

/** PokéAPI names triggers in English only. */
const TRIGGER_KO_NAMES: Record<string, string> = {
  'level-up': '레벨업',
  'use-item': '도구 사용',
  trade: '통신교환',
  shed: '탈피',
  'meltan-candies': 'Pokémon GO에서 멜탄의 사탕 400개',
  spin: '빙글빙글 돌기',
  'three-critical-hits': '한 배틀에서 급소 3번',
  'take-damage': '고인돌 아래 지나기',
  'tower-of-darkness': '악의 탑에서 수행',
  'tower-of-waters': '물의 탑에서 수행',
  'agile-style-move': '속공으로 쓰기',
  'recoil-damage': '반동 데미지 받기',
  'use-move': '쓰기',
  'in-battle-level-up': '배틀 중 레벨업',
  'three-defeated-bisharp': '대장의징표를 지닌 절각참 3마리 쓰러뜨리기',
  'gimmighoul-coins': '모으령의코인 999개 모으기',
}

/**
 * PokéAPI names locations in English only, and only those an evolution in a
 * kept game asks for are needed.
 */
const LOCATION_KO_NAMES: Record<string, string> = {
  'mt-coronet': '천관산',
  'eterna-forest': '영원의숲',
  'sinnoh-route-217': '217번도로',
  'vast-poni-canyon': '포니대협곡',
  'mount-lanakila': '라나키라마운틴',
  'dusty-bowl': '모래먼지구덩이',
}

const triggers = new Map<string, Record<string, string>>()
const items = new Map<string, Record<string, string>>()
const moves = new Map<string, Record<string, string>>()
const moveTypes = new Map<string, string>()
const locations = new Map<string, Record<string, string>>()
const regions = new Map<string, Record<string, string>>()
const versions = new Map<string, Record<string, string>>()

/** The regions whose generation is in, filled before the chains are read. */
const keptRegions = new Set<string>()

type Evolution = {
  id: string
  trigger: string
  level: number | null
  item: string | null
  heldItem: string | null
  happiness: number | null
  timeOfDay: string | null
  physicalStats: number | null
  beauty: number | null
  chance: number | null
  gender: 'female' | 'male' | null
  move: string | null
  location: string | null
  partySpecies: number | null
  partySlug: string | null
  tradeSpecies: number | null
  tradeSlug: string | null
  partyType: string | null
  moveType: string | null
  affection: number | null
  rain: boolean
  upsideDown: boolean
  region: string | null
  version: string | null
  natures: string[] | null
  damage: number | null
  usedMove: string | null
  moveCount: number | null
  steps: number | null
  multiplayer: boolean
}

const methods = new Map<string, Evolution>()

/**
 * What a detail may say that evolution_methods has a column for. PokéAPI
 * also says which games a detail is from, and whether it is the usual way;
 * neither changes what it takes.
 */
const KNOWN_CONDITIONS = new Set([
  'trigger',
  'min_level',
  'item',
  'held_item',
  'min_happiness',
  'time_of_day',
  'relative_physical_stats',
  'min_beauty',
  'gender',
  'known_move',
  'location',
  // The moss and ice rocks Leafeon and Glaceon need are in the place a
  // location names, so the location says it.
  'near_special_rock',
  'party_species',
  'trade_species',
  'party_type',
  'known_move_type',
  'min_affection',
  'needs_overworld_rain',
  'turn_upside_down',
  // Only a kept region's, which ownWay sees to.
  'region',
  // Not PokéAPI's: VERSION_ONLY's.
  'version',
  'condition_expression',
  'required_pokemon_form',
  // ownWay keeps only the one ending in the form asked for.
  'evolved_pokemon_form',
  'version_group',
  'is_default',
  'allowed_natures',
  'min_damage_taken',
  // Wyrdeer's Psyshield Bash, twenty times in the agile style.
  'used_move',
  'min_move_count',
  // Bramblin's thousand steps in Let's Go, and Finizen's Union Circle.
  'min_steps',
  'needs_multiplayer',
])

/** How relative_physical_stats reads in a method's id, Attack against Defense. */
const PHYSICAL_STATS: Record<number, string> = {
  1: 'attack-above-defense',
  0: 'attack-equals-defense',
  [-1]: 'attack-below-defense',
}

/**
 * The variables a condition_expression may hang on that make it a share of
 * Pokémon, fixed for each one: its personality value, or its encryption
 * constant, which took that over in Generation VI.
 */
const PERSONALITY = new Set(['personality-value', 'encryption-constant'])

/**
 * The variables of Milcery's spin, whose way and length pick Alcremie's
 * cream. Only the default Alcremie comes from Milcery here, so they are
 * dropped.
 */
const SPIN = new Set(['spin-direction', 'spin-duration'])

/**
 * The share of Pokémon that go this way, as Wurmple's half to Silcoon and
 * half to Cascoon. PokéAPI writes it as an expression over a variable; any
 * other expression fails here, as a condition without a column does.
 */
function chanceOf(detail: EvolutionDetail): number | null {
  const expression = detail.condition_expression
  if (!expression) return null
  if (expression.variables.every((v) => SPIN.has(v.name))) return null
  if (
    expression.percentage_chance === null ||
    !expression.variables.every((v) => PERSONALITY.has(v.name))
  ) {
    throw new Error(`an evolution condition species has no column for: ${JSON.stringify(detail)}`)
  }
  return expression.percentage_chance
}

/** PokéAPI's genders, as a method names them. */
const GENDERS: Record<number, 'female' | 'male'> = { 1: 'female', 2: 'male' }

/** Whether a detail is in a game that is kept: a later region's is not. */
function inKeptRegion(detail: EvolutionDetail): boolean {
  return !detail.region || keptRegions.has(detail.region.name)
}

/**
 * The detail for one form becoming another. PokéAPI lists a regional form's
 * way beside the rest, such as Alolan Rattata evolving only at night, or
 * Pikachu becoming Alolan Raichu only in Alola; a way that names the form it
 * ends in comes first, so Raichu's own way does not stand for Alolan
 * Raichu's. A species whose every form is named, as Burmy's cloaks are,
 * lists a way per form, each from its form and to its own; with no form to
 * come from, any way to its own will do. A way only Legends: Arceus has
 * comes last, as Overqwil's twenty Barb Barrages in the strong style, where
 * Scarlet and Violet ask only that it know the move.
 */
/** Legends: Arceus's ways by a move used in a style, which no other game asks. */
function styled(detail: EvolutionDetail): boolean {
  return ['agile-style-move', 'strong-style-move'].includes(detail.trigger.name)
}

function ownWay(
  details: EvolutionDetail[],
  from: string | null,
  to: string,
): EvolutionDetail | undefined {
  const fromOk = (d: EvolutionDetail) =>
    !d.required_pokemon_form || from === null || d.required_pokemon_form.name === from
  return (
    details.find((d) => inKeptRegion(d) && d.evolved_pokemon_form?.name === to && fromOk(d)) ??
    [...details]
      .sort((a, b) => Number(styled(a)) - Number(styled(b)))
      .find((d) => !d.region && !d.evolved_pokemon_form && fromOk(d))
  )
}

async function nameItem(item: string) {
  if (items.has(item)) return
  if (ITEMS_NOT_IN_POKEAPI[item]) {
    items.set(item, ITEMS_NOT_IN_POKEAPI[item].names)
    return
  }
  const fetched = await get<{ names: ({ name: string } & Localised)[] }>(`item/${item}`)
  items.set(
    item,
    localise(fetched.names, (n) => n.name),
  )
}

async function nameMove(move: string) {
  if (moves.has(move)) return
  const fetched = await get<{ names: ({ name: string } & Localised)[]; type: Named }>(
    `move/${move}`,
  )
  moveTypes.set(move, fetched.type.name)
  moves.set(
    move,
    localise(fetched.names, (n) => n.name),
  )
}

async function nameLocation(location: string) {
  if (locations.has(location)) return
  const ko = LOCATION_KO_NAMES[location]
  if (!ko) throw new Error(`no Korean name for the location ${location}`)
  const fetched = await get<{ names: ({ name: string } & Localised)[] }>(`location/${location}`)
  locations.set(location, { ...localise(fetched.names, (n) => n.name), ko })
}

async function nameRegion(region: string) {
  if (regions.has(region)) return
  const fetched = await get<{ names: ({ name: string } & Localised)[] }>(`region/${region}`)
  regions.set(
    region,
    localise(fetched.names, (n) => n.name),
  )
}

async function nameVersion(version: string) {
  if (versions.has(version)) return
  const fetched = await get<{ names: ({ name: string } & Localised)[] }>(`version/${version}`)
  versions.set(
    version,
    localise(fetched.names, (n) => n.name),
  )
}

/**
 * How a form is reached, as a row of evolution_methods named for what it is.
 * A method has a column for each condition Generations I to IX ask; anything
 * else fails here rather than being dropped, so a wider table grows the
 * columns it needs.
 */
async function evolutionOf(detail: EvolutionDetail): Promise<Evolution> {
  const unknown = Object.entries(detail).filter(
    ([key, value]) =>
      !KNOWN_CONDITIONS.has(key) && value !== null && value !== '' && value !== false,
  )
  if (unknown.length > 0) {
    throw new Error(`an evolution condition species has no column for: ${JSON.stringify(detail)}`)
  }
  const trigger = detail.trigger.name
  if (!triggers.has(trigger) && TRIGGERS_NOT_IN_POKEAPI[trigger]) {
    triggers.set(trigger, TRIGGERS_NOT_IN_POKEAPI[trigger])
  }
  if (!triggers.has(trigger)) {
    const ko = TRIGGER_KO_NAMES[trigger]
    if (!ko) throw new Error(`no Korean name for the trigger ${trigger}`)
    const fetched = await get<{ names: ({ name: string } & Localised)[] }>(
      `evolution-trigger/${trigger}`,
    )
    triggers.set(trigger, { ...localise(fetched.names, (n) => n.name), ko })
  }
  const item = detail.item?.name ?? null
  const heldItem = detail.held_item?.name ?? null
  for (const named of [item, heldItem]) if (named) await nameItem(named)
  const level = detail.min_level ?? null
  const happiness = detail.min_happiness ?? null
  const timeOfDay = detail.time_of_day || null
  const physicalStats = detail.relative_physical_stats ?? null
  const beauty = detail.min_beauty ?? null
  const chance = chanceOf(detail)
  const gender = detail.gender ? GENDERS[detail.gender] : null
  const move = detail.known_move?.name ?? null
  if (move) await nameMove(move)
  const location = detail.location?.name ?? null
  if (location) await nameLocation(location)
  const partySlug = detail.party_species?.name ?? null
  const partySpecies = detail.party_species ? idOf(detail.party_species) : null
  const tradeSlug = detail.trade_species?.name ?? null
  const tradeSpecies = detail.trade_species ? idOf(detail.trade_species) : null
  const partyType = detail.party_type?.name ?? null
  const moveType = detail.known_move_type?.name ?? null
  const affection = detail.min_affection ?? null
  const rain = detail.needs_overworld_rain === true
  const upsideDown = detail.turn_upside_down === true
  const region = detail.region?.name ?? null
  if (region) await nameRegion(region)
  const version = (detail.version as string | undefined) ?? null
  if (version) await nameVersion(version)
  const natures = detail.allowed_natures
    ? (detail.allowed_natures as Named[]).map((n) => n.name).sort()
    : null
  const damage = (detail.min_damage_taken as number | null | undefined) ?? null
  const usedMove = (detail.used_move as Named | null | undefined)?.name ?? null
  if (usedMove) await nameMove(usedMove)
  const moveCount = (detail.min_move_count as number | null | undefined) ?? null
  const steps = (detail.min_steps as number | null | undefined) ?? null
  const multiplayer = detail.needs_multiplayer === true
  const id = [
    trigger,
    level,
    item,
    heldItem && `holding-${heldItem}`,
    happiness && `happiness-${happiness}`,
    timeOfDay,
    physicalStats !== null && PHYSICAL_STATS[physicalStats],
    beauty && `beauty-${beauty}`,
    chance && `chance-${chance}`,
    gender,
    move && `knowing-${move}`,
    location && `at-${location}`,
    partySlug && `with-${partySlug}`,
    tradeSlug && `for-${tradeSlug}`,
    moveType && `knowing-${moveType}-move`,
    affection && `affection-${affection}`,
    partyType && `with-${partyType}-type`,
    rain && 'in-rain',
    upsideDown && 'upside-down',
    region && `in-${region}`,
    version && `in-${version}`,
    natures && `${natures[0]}-or-${natures.length - 1}-more-natures`,
    damage && `after-${damage}-damage`,
    usedMove && `using-${usedMove}-${moveCount}-times`,
    steps && `after-${steps}-steps`,
    multiplayer && 'in-union-circle',
  ]
    .filter((part) => part !== null && part !== false)
    .join('-')
  if (!methods.has(id)) {
    methods.set(id, {
      id,
      trigger,
      level,
      item,
      heldItem,
      happiness,
      timeOfDay,
      physicalStats,
      beauty,
      chance,
      gender,
      move,
      location,
      partySpecies,
      partySlug,
      tradeSpecies,
      tradeSlug,
      partyType,
      moveType,
      affection,
      rain,
      upsideDown,
      region,
      version,
      natures,
      damage,
      usedMove,
      moveCount,
      steps,
      multiplayer,
    })
  }
  return methods.get(id)!
}

type Row = {
  id: number
  slug: string
  dexNo: number
  generation: number
  names: Record<string, string>
  formNames: Record<string, string>
  formOf: number | null
  genus: Record<string, string>
  flavor: Species['flavor_text_entries']
  types: string[]
  stats: Record<string, number>
  height: number
  weight: number
  growthRate: string
  captureRate: number
  hatchCounter: number
  genderRate: number
  category: 'baby' | 'legendary' | 'mythical' | null
  evolvesFrom: number | null
  evolution: Evolution | null
  sprites: Record<string, string>
  /** The file each style is under in PokeAPI/sprites: a Pokémon's id, or its number and form. */
  spriteKey: string
  /** Whether a female looks different, as Pikachu's tail does. */
  femaleDiffers: boolean
}

const STATS: Record<string, string> = {
  hp: 'hp',
  attack: 'attack',
  defense: 'defense',
  'special-attack': 'special_attack',
  'special-defense': 'special_defense',
  speed: 'speed',
}

function sql(value: unknown): string {
  if (value === null || value === undefined) return 'null'
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  const text = typeof value === 'string' ? value : JSON.stringify(value)
  return `'${text.replaceAll("'", "''")}'`
}

/** Rows into a table, each replacing the one already under its key. */
/**
 * Every row the earlier generated migrations wrote, under its table and
 * columns. A row written with other columns, before one was added, counts as
 * not written.
 */
async function writtenBefore(): Promise<Set<string>> {
  const dir = new URL('./', `file://${MIGRATION}`)
  const earlier = (await readdir(dir))
    .filter((f) => f.endsWith('_pokedex_data.sql') && f < MIGRATION.split('/').pop()!)
    .sort()
  const written = new Set<string>()
  for (const file of earlier) {
    const text = await readFile(new URL(file, dir), 'utf8')
    for (const [, head, values] of text.matchAll(
      /^(insert into .*? values)\n([\s\S]*?)\non conflict/gm,
    )) {
      for (const row of values.split(/,\n(?=  \()/)) written.add(`${head}\n${row}`)
    }
  }
  return written
}

/**
 * Every pokedex_species id the earlier generated migrations wrote and did not
 * delete after.
 */
async function speciesBefore(): Promise<Set<number>> {
  const dir = new URL('./', `file://${MIGRATION}`)
  const earlier = (await readdir(dir))
    .filter((f) => f.endsWith('_pokedex_data.sql') && f < MIGRATION.split('/').pop()!)
    .sort()
  const ids = new Set<number>()
  for (const file of earlier) {
    const text = await readFile(new URL(file, dir), 'utf8')
    for (const [, values] of text.matchAll(
      /^insert into public\.pokedex_species .*? values\n([\s\S]*?)\non conflict/gm,
    )) {
      for (const [, id] of values.matchAll(/^  \((\d+), /gm)) ids.add(Number(id))
    }
    for (const [, list] of text.matchAll(
      /^delete from public\.pokedex_species where id in \(([^)]*)\);/gm,
    )) {
      for (const id of list.split(', ')) ids.delete(Number(id))
    }
  }
  return ids
}

/** An upsert of the rows not written before, or nothing if there are none. */
function upsert(
  written: Set<string>,
  table: string,
  columns: string[],
  key: string[],
  all: string[],
): string[] {
  const head = `insert into public.${table} (${columns.join(', ')}) values`
  const values = all.filter((v) => !written.has(`${head}\n${v}`))
  if (values.length === 0) return []
  const rest = columns.filter((c) => !key.includes(c))
  const onConflict =
    rest.length === 0
      ? 'do nothing'
      : `do update set\n  ${rest.map((c) => `${c} = excluded.${c}`).join(',\n  ')}`
  return [head, values.join(',\n'), `on conflict (${key.join(', ')}) ${onConflict};`, '']
}

async function sha256Of(url: string): Promise<string> {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${url}: ${response.status}`)
  return createHash('sha256')
    .update(Buffer.from(await response.arrayBuffer()))
    .digest('hex')
}

async function main() {
  // A hundred at a time: all 649 at once time out on connecting.
  const species: Species[] = []
  for (let start = 1; start <= LAST_DEX_NO; start += 100) {
    const count = Math.min(100, LAST_DEX_NO - start + 1)
    species.push(
      ...(await Promise.all(
        Array.from({ length: count }, (_, i) => get<Species>(`pokemon-species/${start + i}`)),
      )),
    )
  }
  // Every form of every species that its generation's games had: a Pokémon of
  // its own, as Heat Rotom is, or a form of one, as Unown B is. A species'
  // default form has its national number for an id; the rest are 10001 on.
  type Kept = { form: Form; pokemon: Pokemon }
  const generations = new Map<string, Promise<number>>()
  const generationOf = (group: Named) => {
    if (!generations.has(group.name)) {
      generations.set(
        group.name,
        get<{ generation: Named }>(group.url).then((g) => idOf(g.generation)),
      )
    }
    return generations.get(group.name)!
  }
  const keptOf = async (s: Species): Promise<Kept[]> => {
    const kept: Kept[] = []
    for (const variety of s.varieties) {
      const pokemon = await get<Pokemon>(variety.pokemon.url)
      for (const form of await Promise.all(pokemon.forms.map((f) => get<Form>(f.url)))) {
        if (LEFT_OUT_FORMS.has(form.name) || form.name.endsWith('-gmax')) continue
        if (ONE_FORM_ONLY.has(s.name) && !form.is_default) continue
        if ((await generationOf(form.version_group)) > LAST_GENERATION) continue
        if (LATER_VERSION_GROUPS.has(form.version_group.name)) continue
        kept.push({ form, pokemon })
      }
    }
    if (!kept.some((k) => k.form.id === s.id)) throw new Error(`no default form for ${s.name}`)
    return kept.sort((a, b) => a.form.id - b.form.id)
  }
  const formsOf = new Map<number, Kept[]>()
  for (let start = 0; start < species.length; start += 100) {
    const batch = species.slice(start, start + 100)
    const kept = await Promise.all(batch.map(keptOf))
    batch.forEach((s, i) => formsOf.set(s.id, kept[i]))
  }
  const defaultOf = (id: number) => formsOf.get(id)!.find((k) => k.form.id === id)!

  // Which form each form evolves from, and on what, from the chains. A link to
  // or from a species outside the table is dropped, and so is one that asks
  // for nothing: PokéAPI puts Phione in Manaphy's chain, since a Manaphy's egg
  // hatches Phione, but Phione never becomes Manaphy.
  //
  // A default form evolves from the default form before it. Another form
  // evolves from the form of the same name, as East Sea Gastrodon from East
  // Sea Shellos, and from nothing where there is none: Sunshine Cherrim is
  // only Cherrim in the sun. A form with none of its name before it that a
  // way names for its own, as female Meowstic is a female Espurr's, evolves
  // from the form that way asks for, or else from the default form.
  const reached = new Map<number, { from: number; detail: EvolutionDetail }>()
  const { results: allRegions } = await get<{ results: Named[] }>('region?limit=100')
  for (const region of allRegions) {
    const { main_generation } = await get<{ main_generation: Named | null }>(region.url)
    const generation = main_generation ? idOf(main_generation) : REGION_GENERATIONS[region.name]
    if (generation && generation <= LAST_GENERATION) keptRegions.add(region.name)
  }
  const chainUrls = [...new Set(species.map((s) => s.evolution_chain.url))]
  for (const url of chainUrls) {
    const { chain } = await get<{ chain: ChainLink }>(url)
    const walk = (link: ChainLink) => {
      for (const next of link.evolves_to) {
        const from = idOf(link.species)
        const to = idOf(next.species)
        if (from <= LAST_DEX_NO && to <= LAST_DEX_NO && next.evolution_details.length > 0) {
          for (const target of formsOf.get(to)!) {
            const named = next.evolution_details.find(
              (d) => inKeptRegion(d) && d.evolved_pokemon_form?.name === target.form.name,
            )
            // Dusk Lycanroc's way asks for Own Tempo Rockruff.
            const namedSource =
              named &&
              (formsOf.get(from)!.find((k) => k.form.name === named.required_pokemon_form?.name) ??
                defaultOf(from))
            const fromDefault = ONLY_DEFAULT_EVOLVES.has(next.species.name)
            if (fromDefault && target.form.id !== to) continue
            // Perrserker comes only from Galarian Meowth: a species every way
            // to which asks for another form comes from that form.
            const asked = next.evolution_details.every((d) => d.required_pokemon_form)
              ? formsOf
                  .get(from)!
                  .find(
                    (k) => k.form.name === next.evolution_details[0].required_pokemon_form?.name,
                  )
              : undefined
            const source =
              target.form.id === to
                ? (asked ?? defaultOf(from))
                : (formsOf.get(from)!.find((k) => k.form.form_name === target.form.form_name) ??
                  namedSource ??
                  undefined)
            if (!source) continue
            const detail = ownWay(
              next.evolution_details,
              fromDefault ? null : source.form.name,
              target.form.name,
            )
            if (!detail)
              throw new Error(`no way of its own from ${source.form.name} to ${target.form.name}`)
            const version = VERSION_ONLY[target.form.name]
            reached.set(target.form.id, {
              from: source.form.id,
              detail: version ? { ...detail, version } : detail,
            })
          }
        }
        walk(next)
      }
    }
    walk(chain)
  }
  // Every Mega Evolution, Primal Reversion and Ultra Burst kept, from its
  // default form.
  for (const s of species) {
    for (const { form } of formsOf.get(s.id)!) {
      const mega = MEGA_EVOLUTIONS[form.name]
      if (!mega && /-(mega|primal|ultra)(-|$)/.test(form.name))
        throw new Error(`no Mega Evolution listed for ${form.name}`)
      if (!mega) continue
      const named = (name: string) => ({ name, url: '' })
      reached.set(form.id, {
        from: s.id,
        detail: {
          trigger: named(mega.trigger),
          held_item: mega.item ? named(mega.item) : null,
          known_move: mega.move ? named(mega.move) : null,
        } as EvolutionDetail,
      })
    }
  }

  const rows: Row[] = []
  for (const s of species) {
    const kept = formsOf.get(s.id)!
    for (const { form, pokemon } of kept) {
      const evolution = reached.get(form.id)
      // Named only where there is more than one to tell apart, so Greninja,
      // whose Ash-Greninja is left out, has no name for its one.
      const formNames: Record<string, string> =
        kept.length > 1 ? localise(form.form_names, (n) => n.name) : {}
      if (kept.length > 1 && FORM_KO_NAMES[form.name]) formNames.ko = FORM_KO_NAMES[form.name]
      else if (kept.length > 1 && form.name.endsWith('-hisui') && !formNames.ko)
        formNames.ko = HISUIAN_KO
      // PokéAPI names a few default forms nothing, as Pichu's; a screen calls
      // those 기본. Any other form it cannot name is a name missing here.
      if (kept.length > 1 && form.id !== s.id && !formNames.ko)
        throw new Error(`no Korean name for the form ${form.name}`)
      const types = form.types.length > 0 ? form.types : pokemon.types
      // Of the species' default form only: no other form kept has a female of
      // its own. PokéAPI's front_female is no guide, as it gives Nidoran♀
      // her one sprite there. Where a female is a form, as Meowstic's is, the
      // default form is the male alone.
      const femaleDiffers =
        s.has_gender_differences &&
        form.id === s.id &&
        !kept.some((k) => k.form.form_name === 'female')
      rows.push({
        id: form.id,
        slug: form.name,
        dexNo: s.id,
        generation: idOf(s.generation),
        names: localise(s.names, (n) => n.name),
        formNames,
        formOf: form.id === s.id ? null : s.id,
        genus: localise(s.genera, (g) => g.genus),
        flavor: s.flavor_text_entries,
        types: [...types].sort((a, b) => a.slot - b.slot).map((t) => t.type.name),
        stats: Object.fromEntries(pokemon.stats.map((st) => [STATS[st.stat.name], st.base_stat])),
        height: pokemon.height,
        weight: pokemon.weight,
        growthRate: s.growth_rate.name,
        captureRate: s.capture_rate,
        hatchCounter: s.hatch_counter,
        genderRate: s.gender_rate,
        category: s.is_baby
          ? 'baby'
          : s.is_legendary
            ? 'legendary'
            : s.is_mythical
              ? 'mythical'
              : null,
        evolvesFrom: evolution ? evolution.from : null,
        evolution: evolution ? await evolutionOf(evolution.detail) : null,
        // Under the form's id, which is the national number for a default form.
        // A female that looks different has sprites of her own, in pixels and
        // large.
        sprites: {
          front: `/sprites/pokemon/${form.id}.png`,
          front_shiny: `/sprites/pokemon/shiny/${form.id}.png`,
          ...(femaleDiffers && {
            front_female: `/sprites/pokemon/female/${form.id}.png`,
            front_shiny_female: `/sprites/pokemon/shiny/female/${form.id}.png`,
          }),
          artwork: `/sprites/pokemon/artwork/${form.id}.png`,
          artwork_shiny: `/sprites/pokemon/artwork/shiny/${form.id}.png`,
          ...(femaleDiffers && {
            artwork_female: `/sprites/pokemon/artwork/female/${form.id}.png`,
            artwork_shiny_female: `/sprites/pokemon/artwork/shiny/female/${form.id}.png`,
          }),
        },
        // PokeAPI/sprites files a Pokémon's own default form by the Pokémon's
        // id, as 10008 for Heat Rotom, and its other forms by number and form,
        // as 201-b for Unown B. Pokémon and form ids differ: form 10001 is Unown
        // B, and Pokémon 10001 is Attack Forme Deoxys.
        spriteKey: form.is_default ? String(pokemon.id) : `${s.id}-${form.form_name}`,
        femaleDiffers,
      })
    }
  }

  // Each pokedex's numbering, and its entry text in the game it prefers.
  // PokéAPI lists a species' entries oldest first. Every form of a species is
  // under its number, with the same text, and the default form is the one a
  // list shows.
  const byDexNo = new Map<number, Row[]>()
  for (const row of rows) byDexNo.set(row.dexNo, [...(byDexNo.get(row.dexNo) ?? []), row])
  const entries: {
    dex: string
    number: number
    row: Row
    isDefault: boolean
    description: Record<string, string>
  }[] = []
  for (const [dex, { apiId, versions, appended = [] }] of Object.entries(POKEDEXES)) {
    // A pokedex in sections numbers each on from the one before, and lists a
    // species once, under the first number it had.
    const listed: { entry_number: number; pokemon_species: { url: string } }[] = []
    for (const id of [apiId].flat()) {
      const section = await get<{
        pokemon_entries: { entry_number: number; pokemon_species: { url: string } }[]
      }>(`pokedex/${id}`)
      const seen = new Set(listed.map((e) => idOf(e.pokemon_species)))
      const before = listed.length > 0 ? Math.max(...listed.map((e) => e.entry_number)) : 0
      let skipped = 0
      for (const e of [...section.pokemon_entries].sort(
        (a, b) => a.entry_number - b.entry_number,
      )) {
        if (appended.includes(idOf(e.pokemon_species))) continue
        if (seen.has(idOf(e.pokemon_species))) {
          skipped += 1
          continue
        }
        listed.push({ ...e, entry_number: before + e.entry_number - skipped })
      }
    }
    const last = Math.max(...listed.map((e) => e.entry_number))
    for (const entry of [
      ...listed,
      ...appended.map((id, i) => ({
        entry_number: last + 1 + i,
        pokemon_species: { url: `pokemon-species/${id}/` },
      })),
    ]) {
      const forms = byDexNo.get(idOf(entry.pokemon_species))
      if (!forms) continue
      const description = localise(
        forms[0].flavor,
        (f) => prose(f.flavor_text),
        (matching) =>
          versions.map((v) => matching.find((f) => f.version.name === v)).find(Boolean) ??
          matching.at(-1),
      )
      for (const row of forms) {
        entries.push({
          dex,
          number: entry.entry_number,
          row,
          isDefault: row.formOf === null,
          description,
        })
      }
    }
  }

  const typeIds = [...new Set(rows.flatMap((r) => r.types))].sort()
  const typeNames = new Map<string, Record<string, string>>()
  // Attacking type, then defending type, to the damage as a percentage.
  const efficacy = new Map<string, Map<string, number>>()
  for (const id of typeIds) {
    const type = await get<{
      names: ({ name: string } & Localised)[]
      damage_relations: Record<'double_damage_to' | 'half_damage_to' | 'no_damage_to', Named[]>
    }>(`type/${id}`)
    typeNames.set(
      id,
      localise(type.names, (n) => n.name),
    )
    const factors = new Map<string, number>()
    for (const t of type.damage_relations.double_damage_to) factors.set(t.name, 200)
    for (const t of type.damage_relations.half_damage_to) factors.set(t.name, 50)
    for (const t of type.damage_relations.no_damage_to) factors.set(t.name, 0)
    efficacy.set(id, factors)
  }

  const rates = [...new Set(rows.map((r) => r.growthRate))].sort()
  const levels = new Map<string, { level: number; experience: number }[]>()
  for (const rate of rates) {
    levels.set(
      rate,
      (await get<{ levels: { level: number; experience: number }[] }>(`growth-rate/${rate}`))
        .levels,
    )
  }

  for (const item of GAME_ITEMS) await nameItem(item)

  // The commit is pinned, so a hash the manifest already has for a source is
  // still that file's, and a run fetches only what is new.
  const known = new Map<string, string>()
  try {
    const previous = JSON.parse(await readFile(MANIFEST, 'utf8')) as {
      commit: string
      files: { source: string; sha256: string }[]
    }
    if (previous.commit === SPRITES_COMMIT) {
      for (const f of previous.files) known.set(f.source, f.sha256)
    }
  } catch {
    // No manifest yet: every file is fetched.
  }
  const files: { path: string; source: string }[] = []
  const add = (path: string, source: string) => files.push({ path, source })
  // A list shows the 96px front sprite, the one style every generation has
  // in pixels. A Pokémon's own page shows its render from Pokémon HOME, the
  // one large style with every species, its shiny and, where she looks
  // different, its female, and which stays sharp at any size. The official
  // artwork draws no females.
  add('sprites/egg.png', `${SPRITES_BASE}/egg.png`)
  // Every item an evolution names, in the bag's 30px pixel style.
  for (const id of [...items.keys()].sort())
    if (!DRAWN_ITEMS.has(id))
      add(`sprites/items/${id}.png`, `${ITEMS_BASE}/${ITEMS_NOT_IN_POKEAPI[id]?.sprite ?? id}.png`)
  const home = `${SPRITES_BASE}/other/home`
  for (const row of rows) {
    const n = row.id
    const k = row.spriteKey
    const shiny = NEVER_SHINY.has(row.slug) ? '' : 'shiny/'
    add(`sprites/pokemon/${n}.png`, `${SPRITES_BASE}/${k}.png`)
    add(`sprites/pokemon/shiny/${n}.png`, `${SPRITES_BASE}/${shiny}${k}.png`)
    if (row.femaleDiffers) {
      add(`sprites/pokemon/female/${n}.png`, `${SPRITES_BASE}/female/${k}.png`)
      add(`sprites/pokemon/shiny/female/${n}.png`, `${SPRITES_BASE}/shiny/female/${k}.png`)
    }
    add(`sprites/pokemon/artwork/${n}.png`, `${home}/${k}.png`)
    add(`sprites/pokemon/artwork/shiny/${n}.png`, `${home}/${shiny}${k}.png`)
    if (row.femaleDiffers) {
      add(`sprites/pokemon/artwork/female/${n}.png`, `${home}/female/${k}.png`)
      add(`sprites/pokemon/artwork/shiny/female/${n}.png`, `${home}/shiny/female/${k}.png`)
    }
  }
  // Sixteen at a time, in the manifest's order.
  const sprites: { path: string; source: string; sha256: string }[] = []
  for (let start = 0; start < files.length; start += 16) {
    sprites.push(
      ...(await Promise.all(
        files
          .slice(start, start + 16)
          .map(async (f) => ({ ...f, sha256: known.get(f.source) ?? (await sha256Of(f.source)) })),
      )),
    )
  }

  await writeFile(
    MANIFEST,
    JSON.stringify({ notice: SPRITES_NOTICE, commit: SPRITES_COMMIT, files: sprites }, null, 2) +
      '\n',
  )

  // A row's pre-evolution and default form go in first, so evolves_from_id
  // and form_of always find theirs.
  const inserted = new Set<number>()
  const ordered: Row[] = []
  while (ordered.length < rows.length) {
    for (const row of rows) {
      if (inserted.has(row.id)) continue
      if (
        (row.evolvesFrom === null || inserted.has(row.evolvesFrom)) &&
        (row.formOf === null || inserted.has(row.formOf))
      ) {
        ordered.push(row)
        inserted.add(row.id)
      }
    }
  }

  const written = await writtenBefore()
  // A form left out after an earlier migration wrote it goes, its entries
  // first. Nobody can have one: an egg hatches no such form, and none is a
  // stage a Pokémon evolves into.
  const keptIds = new Set(rows.map((r) => r.id))
  const gone = [...(await speciesBefore())].filter((id) => !keptIds.has(id)).sort((a, b) => a - b)
  const out = [
    '-- Generated by apps/pokedex-web/scripts/generate.ts from PokéAPI. Do not edit;',
    '-- change the script and run it again.',
    '--',
    `-- ${POKEAPI_NOTICE}`,
    '-- The licence is in LICENSES/PokeAPI-BSD-3-Clause.txt.',
    '--',
    '-- With the earlier generated migrations, it says every form up to national',
    `-- No.${LAST_DEX_NO} that its games had, ${rows.length} of them, and their entries in the`,
    `-- ${Object.keys(POKEDEXES).join(', ')} pokedexes. Only the rows that differ from what`,
    '-- those wrote are here, and the forms they wrote that are no longer in.',
    '',
    ...upsert(
      written,
      'pokedex_types',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      typeIds.map(
        (id) => `  (${sql(id)}, ${sql(typeNames.get(id)!.ko)}, ${sql(typeNames.get(id)!.en)})`,
      ),
    ),
    ...upsert(
      written,
      'pokedex_type_efficacy',
      ['attacking_type', 'defending_type', 'damage_factor'],
      ['attacking_type', 'defending_type'],
      typeIds.flatMap((a) =>
        typeIds.map((d) => `  (${sql(a)}, ${sql(d)}, ${efficacy.get(a)!.get(d) ?? 100})`),
      ),
    ),
    ...upsert(
      written,
      'pokedex_growth_rates',
      ['id'],
      ['id'],
      rates.map((r) => `  (${sql(r)})`),
    ),
    ...upsert(
      written,
      'pokedex_experience_levels',
      ['growth_rate', 'level', 'exp'],
      ['growth_rate', 'level'],
      rates.flatMap((rate) =>
        levels
          .get(rate)!
          .sort((a, b) => a.level - b.level)
          .map((l) => `  (${sql(rate)}, ${l.level}, ${l.experience})`),
      ),
    ),
    ...upsert(
      written,
      'pokedex_evolution_triggers',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      [...triggers]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([id, names]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`),
    ),
    ...upsert(
      written,
      'pokedex_items',
      ['id', 'ko_name', 'en_name', 'sprite'],
      ['id'],
      [...items]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(
          ([id, names]) =>
            `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)}, ${sql(`/${DRAWN_ITEMS.has(id) ? 'drawn' : 'sprites'}/items/${id}.png`)})`,
        ),
    ),
    ...upsert(
      written,
      'pokedex_moves',
      ['id', 'ko_name', 'en_name', 'type'],
      ['id'],
      [...moves]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(
          ([id, names]) =>
            `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)}, ${sql(moveTypes.get(id)!)})`,
        ),
    ),
    ...upsert(
      written,
      'pokedex_locations',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      [...locations]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([id, names]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`),
    ),
    ...upsert(
      written,
      'pokedex_regions',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      [...regions]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([id, names]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`),
    ),
    ...upsert(
      written,
      'pokedex_versions',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      [...versions]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([id, names]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`),
    ),
    ...upsert(
      written,
      'pokedex_evolution_methods',
      [
        'id',
        'trigger',
        'level',
        'item',
        'held_item',
        'min_happiness',
        'time_of_day',
        'relative_physical_stats',
        'min_beauty',
        'chance',
        'gender',
        'known_move',
        'location',
        'party_species_id',
        'trade_species_id',
        'party_type',
        'known_move_type',
        'min_affection',
        'needs_overworld_rain',
        'turn_upside_down',
        'region',
        'version',
        'natures',
        'min_damage_taken',
        'used_move',
        'min_move_count',
        'min_steps',
        'needs_multiplayer',
      ],
      ['id'],
      [...methods.values()]
        .sort((a, b) => a.id.localeCompare(b.id, 'en', { numeric: true }))
        .map(
          (m) =>
            `  (${sql(m.id)}, ${sql(m.trigger)}, ${sql(m.level)}, ${sql(m.item)},` +
            ` ${sql(m.heldItem)}, ${sql(m.happiness)}, ${sql(m.timeOfDay)}, ${sql(m.physicalStats)},` +
            ` ${sql(m.beauty)}, ${sql(m.chance)}, ${sql(m.gender)}, ${sql(m.move)},` +
            ` ${sql(m.location)}, ${sql(m.partySpecies)}, ${sql(m.tradeSpecies)},` +
            ` ${sql(m.partyType)}, ${sql(m.moveType)}, ${sql(m.affection)}, ${m.rain}, ${m.upsideDown},` +
            ` ${sql(m.region)}, ${sql(m.version)},` +
            ` ${m.natures ? sql(`{${m.natures.join(',')}}`) : 'null'}, ${sql(m.damage)},` +
            ` ${sql(m.usedMove)}, ${sql(m.moveCount)}, ${sql(m.steps)}, ${m.multiplayer})`,
        ),
    ),
    ...upsert(
      written,
      'pokedex_species',
      [
        'id',
        'slug',
        'ko_name',
        'en_name',
        'ko_form_name',
        'en_form_name',
        'form_of',
        'ko_genus',
        'en_genus',
        'generation',
        'category',
        'type1',
        'type2',
        'hp',
        'attack',
        'defense',
        'special_attack',
        'special_defense',
        'speed',
        'height',
        'weight',
        'growth_rate',
        'capture_rate',
        'hatch_counter',
        'gender_rate',
        'evolves_from_id',
        'evolution_method',
        'sprites',
      ],
      ['id'],
      ordered.map((r) =>
        [
          `  (${r.id}, ${sql(r.slug)}, ${sql(r.names.ko)}, ${sql(r.names.en)},` +
            ` ${sql(r.formNames.ko)}, ${sql(r.formNames.en)}, ${sql(r.formOf)}, ${sql(r.genus.ko)}, ${sql(r.genus.en)},` +
            ` ${r.generation}, ${sql(r.category)},`,
          `   ${sql(r.types[0])}, ${sql(r.types[1] ?? null)}, ${r.stats.hp}, ${r.stats.attack}, ${r.stats.defense},` +
            ` ${r.stats.special_attack}, ${r.stats.special_defense}, ${r.stats.speed}, ${r.height}, ${r.weight},`,
          `   ${sql(r.growthRate)}, ${r.captureRate}, ${r.hatchCounter}, ${r.genderRate},`,
          `   ${sql(r.evolvesFrom)}, ${sql(r.evolution?.id)}, ${sql(r.sprites)})`,
        ].join('\n'),
      ),
    ),
    ...upsert(
      written,
      'pokedex_kinds',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      Object.entries(POKEDEXES).map(
        ([id, { names }]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`,
      ),
    ),
    ...upsert(
      written,
      'pokedex_entries',
      ['dex', 'number', 'species_id', 'is_default', 'ko_description', 'en_description'],
      ['dex', 'species_id'],
      entries.map(
        (e) =>
          `  (${sql(e.dex)}, ${e.number}, ${e.row.id}, ${e.isDefault}, ${sql(e.description.ko)}, ${sql(e.description.en)})`,
      ),
    ),
    ...(gone.length === 0
      ? []
      : [
          `delete from public.pokedex_entries where species_id in (${gone.join(', ')});`,
          `delete from public.pokedex_species where id in (${gone.join(', ')});`,
          '',
        ]),
  ]
  await writeFile(MIGRATION, out.join('\n'))

  console.log(
    `${rows.length} forms, ${entries.length} entries, ${typeIds.length} types, ${sprites.length} sprites`,
  )
}

await main()
