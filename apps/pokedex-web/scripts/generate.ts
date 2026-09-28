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
// earlier ones alone. It upserts every row rather than inserting the new
// ones: a later generation reaches back into an earlier one, as Pichu does
// into Pikachu's row, and the newest migration always says all of it.

import { createHash } from 'node:crypto'
import { readFile, writeFile } from 'node:fs/promises'
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
 * Generations I to IV: national dex numbers 1 to 493, in every form those
 * games had. A form a later game added, such as Alolan Raichu or Mega
 * Venusaur, waits for its generation.
 */
const LAST_DEX_NO = 493
const LAST_GENERATION = 4

/**
 * Forms left out though their generation is in. Arceus's ??? type has no
 * plate to hold, so no game shows it, and no type row to point at.
 */
const LEFT_OUT_FORMS = new Set(['arceus-unknown'])

/**
 * Forms Pokémon HOME never held, so it has no render of them; they take the
 * official artwork instead. Spiky-eared Pichu came to one event in Generation
 * IV and could never leave it.
 */
const NOT_IN_HOME = new Set(['pichu-spiky-eared'])

/** PokéAPI names these forms in English only. */
const FORM_KO_NAMES: Record<string, string> = {
  'pichu-spiky-eared': '삐쭉귀',
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
}

/** The languages kept, Korean and English for now, as PokéAPI codes them. */
const LANGUAGES = ['ko', 'en']

/**
 * The pokedexes kept, with the names PokéAPI lacks in Korean, and which game's
 * entry each prefers, first found wins; with none of them, the newest entry.
 */
const POKEDEXES: Record<
  string,
  { apiId: number; names: Record<string, string>; versions: string[] }
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
  // Diamond and Pearl's, not Platinum's, which lists 59 more, as the others
  // are the first games'.
  sinnoh: {
    apiId: 5,
    names: { ko: '신오도감', en: 'Sinnoh Pokédex' },
    versions: ['brilliant-diamond', 'shining-pearl', 'platinum', 'diamond', 'pearl'],
  },
}

const MANIFEST = fileURLToPath(new URL('../sprites.json', import.meta.url))
const MIGRATION = fileURLToPath(
  new URL('../../../supabase/migrations/20260928120008_pokedex_data.sql', import.meta.url),
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

/** PokéAPI names triggers in English only. */
const TRIGGER_KO_NAMES: Record<string, string> = {
  'level-up': '레벨업',
  'use-item': '도구 사용',
  trade: '통신교환',
  shed: '탈피',
}

/**
 * PokéAPI names locations in English only, and only those an evolution in a
 * kept game asks for are needed.
 */
const LOCATION_KO_NAMES: Record<string, string> = {
  'mt-coronet': '천관산',
  'eterna-forest': '영원의숲',
  'sinnoh-route-217': '217번도로',
}

const triggers = new Map<string, Record<string, string>>()
const items = new Map<string, Record<string, string>>()
const moves = new Map<string, Record<string, string>>()
const locations = new Map<string, Record<string, string>>()

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
  'condition_expression',
  'required_pokemon_form',
  // ownWay keeps only the one ending in the form asked for.
  'evolved_pokemon_form',
  'version_group',
  'is_default',
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
 * The share of Pokémon that go this way, as Wurmple's half to Silcoon and
 * half to Cascoon. PokéAPI writes it as an expression over a variable; any
 * other expression fails here, as a condition without a column does.
 */
function chanceOf(detail: EvolutionDetail): number | null {
  const expression = detail.condition_expression
  if (!expression) return null
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

/**
 * The detail for one form becoming another. PokéAPI lists a regional form's
 * way beside the rest, such as Alolan Rattata evolving only at night, and no
 * regional form is kept yet. A species whose every form is named, as Burmy's
 * cloaks are, lists a way per form, each from its form and to its own.
 */
function ownWay(details: EvolutionDetail[], from: string, to: string): EvolutionDetail | undefined {
  return details.find(
    (d) =>
      !d.region &&
      (!d.evolved_pokemon_form || d.evolved_pokemon_form.name === to) &&
      (!d.required_pokemon_form || d.required_pokemon_form.name === from),
  )
}

async function nameItem(item: string) {
  if (items.has(item)) return
  const fetched = await get<{ names: ({ name: string } & Localised)[] }>(`item/${item}`)
  items.set(
    item,
    localise(fetched.names, (n) => n.name),
  )
}

async function nameMove(move: string) {
  if (moves.has(move)) return
  const fetched = await get<{ names: ({ name: string } & Localised)[] }>(`move/${move}`)
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

/**
 * How a form is reached, as a row of evolution_methods named for what it is.
 * A method has a column for each condition Generations I to IV ask; anything
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
function upsert(table: string, columns: string[], key: string[], values: string[]): string {
  const rest = columns.filter((c) => !key.includes(c))
  const onConflict =
    rest.length === 0
      ? 'do nothing'
      : `do update set\n  ${rest.map((c) => `${c} = excluded.${c}`).join(',\n  ')}`
  return [
    `insert into public.${table} (${columns.join(', ')}) values`,
    values.join(',\n'),
    `on conflict (${key.join(', ')}) ${onConflict};`,
  ].join('\n')
}

async function sha256Of(url: string): Promise<string> {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${url}: ${response.status}`)
  return createHash('sha256')
    .update(Buffer.from(await response.arrayBuffer()))
    .digest('hex')
}

async function main() {
  // A hundred at a time: all 493 at once time out on connecting.
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
        if (LEFT_OUT_FORMS.has(form.name)) continue
        if ((await generationOf(form.version_group)) > LAST_GENERATION) continue
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
  // only Cherrim in the sun.
  const reached = new Map<number, { from: number; detail: EvolutionDetail }>()
  const chainUrls = [...new Set(species.map((s) => s.evolution_chain.url))]
  for (const url of chainUrls) {
    const { chain } = await get<{ chain: ChainLink }>(url)
    const walk = (link: ChainLink) => {
      for (const next of link.evolves_to) {
        const from = idOf(link.species)
        const to = idOf(next.species)
        if (from <= LAST_DEX_NO && to <= LAST_DEX_NO && next.evolution_details.length > 0) {
          for (const target of formsOf.get(to)!) {
            const source =
              target.form.id === to
                ? defaultOf(from)
                : formsOf.get(from)!.find((k) => k.form.form_name === target.form.form_name)
            if (!source) continue
            const detail = ownWay(next.evolution_details, source.form.name, target.form.name)
            if (!detail)
              throw new Error(`no way of its own from ${source.form.name} to ${target.form.name}`)
            reached.set(target.form.id, { from: source.form.id, detail })
          }
        }
        walk(next)
      }
    }
    walk(chain)
  }

  const rows: Row[] = []
  for (const s of species) {
    const kept = formsOf.get(s.id)!
    for (const { form, pokemon } of kept) {
      const evolution = reached.get(form.id)
      // Named only where there is more than one to tell apart, so Kyogre, whose
      // Primal form is a later game's, has no name for its one.
      const formNames: Record<string, string> =
        kept.length > 1 ? localise(form.form_names, (n) => n.name) : {}
      if (kept.length > 1 && FORM_KO_NAMES[form.name]) formNames.ko = FORM_KO_NAMES[form.name]
      // PokéAPI names a few default forms nothing, as Pichu's; a screen calls
      // those 기본. Any other form it cannot name is a name missing here.
      if (kept.length > 1 && form.id !== s.id && !formNames.ko)
        throw new Error(`no Korean name for the form ${form.name}`)
      const types = form.types.length > 0 ? form.types : pokemon.types
      // Of the species' default form only: no other form kept has a female of
      // its own. PokéAPI's front_female is no guide, as it gives Nidoran♀
      // her one sprite there.
      const femaleDiffers = s.has_gender_differences && form.id === s.id
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
  for (const [dex, { apiId, versions }] of Object.entries(POKEDEXES)) {
    const listed = await get<{
      pokemon_entries: { entry_number: number; pokemon_species: Named }[]
    }>(`pokedex/${apiId}`)
    for (const entry of listed.pokemon_entries) {
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
    add(`sprites/items/${id}.png`, `${ITEMS_BASE}/${id}.png`)
  const home = `${SPRITES_BASE}/other/home`
  for (const row of rows) {
    const n = row.id
    const k = row.spriteKey
    add(`sprites/pokemon/${n}.png`, `${SPRITES_BASE}/${k}.png`)
    add(`sprites/pokemon/shiny/${n}.png`, `${SPRITES_BASE}/shiny/${k}.png`)
    if (row.femaleDiffers) {
      add(`sprites/pokemon/female/${n}.png`, `${SPRITES_BASE}/female/${k}.png`)
      add(`sprites/pokemon/shiny/female/${n}.png`, `${SPRITES_BASE}/shiny/female/${k}.png`)
    }
    const large = NOT_IN_HOME.has(row.slug) ? `${SPRITES_BASE}/other/official-artwork` : home
    add(`sprites/pokemon/artwork/${n}.png`, `${large}/${k}.png`)
    add(`sprites/pokemon/artwork/shiny/${n}.png`, `${large}/shiny/${k}.png`)
    if (row.femaleDiffers) {
      add(`sprites/pokemon/artwork/female/${n}.png`, `${large}/female/${k}.png`)
      add(`sprites/pokemon/artwork/shiny/female/${n}.png`, `${large}/shiny/female/${k}.png`)
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

  const out = [
    '-- Generated by apps/pokedex-web/scripts/generate.ts from PokéAPI. Do not edit;',
    '-- change the script and run it again.',
    '--',
    `-- ${POKEAPI_NOTICE}`,
    '-- The licence is in LICENSES/PokeAPI-BSD-3-Clause.txt.',
    '--',
    `-- ${rows.length} forms: every form up to national No.${LAST_DEX_NO} that its games had,`,
    `-- and their entries in the ${Object.keys(POKEDEXES).join(', ')} pokedexes. Every row is`,
    '-- upserted, so this says all of it whatever the migrations before it said.',
    '',
    upsert(
      'pokedex_types',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      typeIds.map(
        (id) => `  (${sql(id)}, ${sql(typeNames.get(id)!.ko)}, ${sql(typeNames.get(id)!.en)})`,
      ),
    ),
    '',
    upsert(
      'pokedex_type_efficacy',
      ['attacking_type', 'defending_type', 'damage_factor'],
      ['attacking_type', 'defending_type'],
      typeIds.flatMap((a) =>
        typeIds.map((d) => `  (${sql(a)}, ${sql(d)}, ${efficacy.get(a)!.get(d) ?? 100})`),
      ),
    ),
    '',
    upsert(
      'pokedex_growth_rates',
      ['id'],
      ['id'],
      rates.map((r) => `  (${sql(r)})`),
    ),
    '',
    upsert(
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
    '',
    upsert(
      'pokedex_evolution_triggers',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      [...triggers]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([id, names]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`),
    ),
    '',
    upsert(
      'pokedex_items',
      ['id', 'ko_name', 'en_name', 'sprite'],
      ['id'],
      [...items]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(
          ([id, names]) =>
            `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)}, ${sql(`/sprites/items/${id}.png`)})`,
        ),
    ),
    '',
    upsert(
      'pokedex_moves',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      [...moves]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([id, names]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`),
    ),
    '',
    upsert(
      'pokedex_locations',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      [...locations]
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([id, names]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`),
    ),
    '',
    upsert(
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
      ],
      ['id'],
      [...methods.values()]
        .sort((a, b) => a.id.localeCompare(b.id, 'en', { numeric: true }))
        .map(
          (m) =>
            `  (${sql(m.id)}, ${sql(m.trigger)}, ${sql(m.level)}, ${sql(m.item)},` +
            ` ${sql(m.heldItem)}, ${sql(m.happiness)}, ${sql(m.timeOfDay)}, ${sql(m.physicalStats)},` +
            ` ${sql(m.beauty)}, ${sql(m.chance)}, ${sql(m.gender)}, ${sql(m.move)},` +
            ` ${sql(m.location)}, ${sql(m.partySpecies)})`,
        ),
    ),
    '',
    upsert(
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
    '',
    upsert(
      'pokedex_kinds',
      ['id', 'ko_name', 'en_name'],
      ['id'],
      Object.entries(POKEDEXES).map(
        ([id, { names }]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`,
      ),
    ),
    '',
    upsert(
      'pokedex_entries',
      ['dex', 'number', 'species_id', 'is_default', 'ko_description', 'en_description'],
      ['dex', 'species_id'],
      entries.map(
        (e) =>
          `  (${sql(e.dex)}, ${e.number}, ${e.row.id}, ${e.isDefault}, ${sql(e.description.ko)}, ${sql(e.description.en)})`,
      ),
    ),
    '',
  ]
  await writeFile(MIGRATION, out.join('\n'))

  console.log(
    `${rows.length} forms, ${entries.length} entries, ${typeIds.length} types, ${sprites.length} sprites`,
  )
}

await main()
