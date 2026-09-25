// Reads PokéAPI once and writes what the rest of the repository needs from it:
// the sprite manifest this app serves from, and the migration that fills the
// pokedex_ tables. Both are committed; nothing reads PokéAPI at build or run
// time.
//
//   node scripts/generate.ts
//
// Run it again only to change what is included. The sprite commit is pinned
// below, so the manifest's hashes stay true until someone moves it.

import { createHash } from 'node:crypto'
import { writeFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'

/** PokeAPI/sprites at the commit every hash in the manifest was taken from. */
const SPRITES_COMMIT = 'a13b1f4ccd77f35fd1370d2db5f0051221e9683f'
const SPRITES_BASE = `https://raw.githubusercontent.com/PokeAPI/sprites/${SPRITES_COMMIT}/sprites/pokemon`

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

/** Generation I: national dex numbers 1 to 151, in their default forms. */
const LAST_DEX_NO = 151

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
}

const MANIFEST = fileURLToPath(new URL('../sprites.json', import.meta.url))
const MIGRATION = fileURLToPath(
  new URL('../../../supabase/migrations/20260923120001_pokedex_data.sql', import.meta.url),
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
  growth_rate: Named
  evolution_chain: { url: string }
  varieties: { is_default: boolean; pokemon: Named }[]
}
type Pokemon = {
  id: number
  height: number
  weight: number
  types: { slot: number; type: Named }[]
  stats: { base_stat: number; stat: Named }[]
  forms: Named[]
}
type EvolutionDetail = {
  trigger: Named
  min_level: number | null
  item: Named | null
  held_item: Named | null
  min_happiness: number | null
  time_of_day: string
}
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
}

const triggers = new Map<string, Record<string, string>>()
const items = new Map<string, Record<string, string>>()

type Evolution = { id: string; trigger: string; level: number | null; item: string | null }

const methods = new Map<string, Evolution>()

/**
 * How a form is reached, as a row of evolution_methods named for what it is.
 * A method has a column for a level and for an item, which is all Generation
 * I asks; anything else fails here rather than being dropped, so a wider
 * table grows the columns it needs.
 */
async function evolutionOf(detail: EvolutionDetail): Promise<Evolution> {
  if (detail.held_item || detail.min_happiness || detail.time_of_day) {
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
  if (item && !items.has(item)) {
    const fetched = await get<{ names: ({ name: string } & Localised)[] }>(`item/${item}`)
    items.set(
      item,
      localise(fetched.names, (n) => n.name),
    )
  }
  const level = detail.min_level ?? null
  const id = [trigger, level, item].filter((part) => part !== null).join('-')
  if (!methods.has(id)) methods.set(id, { id, trigger, level, item })
  return methods.get(id)!
}

type Row = {
  id: number
  slug: string
  dexNo: number
  generation: number
  names: Record<string, string>
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

async function sha256Of(url: string): Promise<string> {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${url}: ${response.status}`)
  return createHash('sha256')
    .update(Buffer.from(await response.arrayBuffer()))
    .digest('hex')
}

async function main() {
  const species = await Promise.all(
    Array.from({ length: LAST_DEX_NO }, (_, i) => get<Species>(`pokemon-species/${i + 1}`)),
  )

  // Who each species evolves from, and on what, from the chains. A link to or
  // from a species outside the table is dropped.
  const reached = new Map<number, { from: number; detail: EvolutionDetail }>()
  const chainUrls = [...new Set(species.map((s) => s.evolution_chain.url))]
  for (const url of chainUrls) {
    const { chain } = await get<{ chain: ChainLink }>(url)
    const walk = (link: ChainLink) => {
      for (const next of link.evolves_to) {
        const from = idOf(link.species)
        const to = idOf(next.species)
        if (from <= LAST_DEX_NO && to <= LAST_DEX_NO && next.evolution_details[0]) {
          reached.set(to, { from, detail: next.evolution_details[0] })
        }
        walk(next)
      }
    }
    walk(chain)
  }

  const rows: Row[] = []
  for (const s of species) {
    const variety = s.varieties.find((v) => v.is_default)!
    const pokemon = await get<Pokemon>(`pokemon/${idOf(variety.pokemon)}`)
    const formId = idOf(pokemon.forms[0])
    const evolution = reached.get(s.id)
    rows.push({
      id: formId,
      slug: pokemon.forms[0].name,
      dexNo: s.id,
      generation: idOf(s.generation),
      names: localise(s.names, (n) => n.name),
      genus: localise(s.genera, (g) => g.genus),
      flavor: s.flavor_text_entries,
      types: pokemon.types.sort((a, b) => a.slot - b.slot).map((t) => t.type.name),
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
      sprites: {
        animated: `/sprites/pokemon/${s.id}.gif`,
        animated_shiny: `/sprites/pokemon/shiny/${s.id}.gif`,
      },
    })
  }

  // Each pokedex's numbering, and its entry text in the game it prefers.
  // PokéAPI lists a species' entries oldest first.
  const byDexNo = new Map(rows.map((r) => [r.dexNo, r]))
  const entries: { dex: string; number: number; row: Row; description: Record<string, string> }[] =
    []
  for (const [dex, { apiId, versions }] of Object.entries(POKEDEXES)) {
    const listed = await get<{
      pokemon_entries: { entry_number: number; pokemon_species: Named }[]
    }>(`pokedex/${apiId}`)
    for (const entry of listed.pokemon_entries) {
      const row = byDexNo.get(idOf(entry.pokemon_species))
      if (!row) continue
      const description = localise(
        row.flavor,
        (f) => prose(f.flavor_text),
        (matching) =>
          versions.map((v) => matching.find((f) => f.version.name === v)).find(Boolean) ??
          matching.at(-1),
      )
      entries.push({ dex, number: entry.entry_number, row, description })
    }
  }

  const typeIds = [...new Set(rows.flatMap((r) => r.types))].sort()
  const typeNames = new Map<string, Record<string, string>>()
  for (const id of typeIds) {
    const type = await get<{ names: ({ name: string } & Localised)[] }>(`type/${id}`)
    typeNames.set(
      id,
      localise(type.names, (n) => n.name),
    )
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

  const sprites: { path: string; source: string; sha256: string }[] = []
  const add = async (path: string, source: string) => {
    sprites.push({ path, source, sha256: await sha256Of(source) })
  }
  await add('sprites/egg.png', `${SPRITES_BASE}/egg.png`)
  const animated = `${SPRITES_BASE}/versions/generation-v/black-white/animated`
  for (const row of rows) {
    await add(`sprites/pokemon/${row.dexNo}.gif`, `${animated}/${row.dexNo}.gif`)
    await add(`sprites/pokemon/shiny/${row.dexNo}.gif`, `${animated}/shiny/${row.dexNo}.gif`)
  }

  await writeFile(
    MANIFEST,
    JSON.stringify({ notice: SPRITES_NOTICE, commit: SPRITES_COMMIT, files: sprites }, null, 2) +
      '\n',
  )

  // A row's pre-evolution goes in first, so evolves_from_id always finds it.
  const inserted = new Set<number>()
  const ordered: Row[] = []
  while (ordered.length < rows.length) {
    for (const row of rows) {
      if (inserted.has(row.id)) continue
      if (row.evolvesFrom === null || inserted.has(row.evolvesFrom)) {
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
    `-- ${rows.length} forms, the default form of every Generation I species, and`,
    `-- their entries in the ${Object.keys(POKEDEXES).join(' and ')} pokedexes.`,
    '',
    'insert into public.pokedex_types (id, ko_name, en_name) values',
    typeIds
      .map((id) => `  (${sql(id)}, ${sql(typeNames.get(id)!.ko)}, ${sql(typeNames.get(id)!.en)})`)
      .join(',\n') + ';',
    '',
    'insert into public.pokedex_growth_rates (id) values',
    rates.map((r) => `  (${sql(r)})`).join(',\n') + ';',
    '',
    'insert into public.pokedex_experience_levels (growth_rate, level, exp) values',
    rates
      .flatMap((rate) =>
        levels
          .get(rate)!
          .sort((a, b) => a.level - b.level)
          .map((l) => `  (${sql(rate)}, ${l.level}, ${l.experience})`),
      )
      .join(',\n') + ';',
    '',
    'insert into public.pokedex_evolution_triggers (id, ko_name, en_name) values',
    [...triggers]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([id, names]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`)
      .join(',\n') + ';',
    '',
    'insert into public.pokedex_items (id, ko_name, en_name) values',
    [...items]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([id, names]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`)
      .join(',\n') + ';',
    '',
    'insert into public.pokedex_evolution_methods (id, trigger, level, item) values',
    [...methods.values()]
      .sort((a, b) => a.id.localeCompare(b.id, 'en', { numeric: true }))
      .map((m) => `  (${sql(m.id)}, ${sql(m.trigger)}, ${sql(m.level)}, ${sql(m.item)})`)
      .join(',\n') + ';',
    '',
    'insert into public.pokedex_species (',
    '  id, slug, ko_name, en_name, ko_genus, en_genus, generation, category,',
    '  type1, type2, hp, attack, defense, special_attack, special_defense, speed, height, weight,',
    '  growth_rate, capture_rate, hatch_counter, gender_rate,',
    '  evolves_from_id, evolution_method, sprites',
    ') values',
    ordered
      .map((r) =>
        [
          `  (${r.id}, ${sql(r.slug)}, ${sql(r.names.ko)}, ${sql(r.names.en)}, ${sql(r.genus.ko)}, ${sql(r.genus.en)},` +
            ` ${r.generation}, ${sql(r.category)},`,
          `   ${sql(r.types[0])}, ${sql(r.types[1] ?? null)}, ${r.stats.hp}, ${r.stats.attack}, ${r.stats.defense},` +
            ` ${r.stats.special_attack}, ${r.stats.special_defense}, ${r.stats.speed}, ${r.height}, ${r.weight},`,
          `   ${sql(r.growthRate)}, ${r.captureRate}, ${r.hatchCounter}, ${r.genderRate},`,
          `   ${sql(r.evolvesFrom)}, ${sql(r.evolution?.id)}, ${sql(r.sprites)})`,
        ].join('\n'),
      )
      .join(',\n') + ';',
    '',
    'insert into public.pokedex_kinds (id, ko_name, en_name) values',
    Object.entries(POKEDEXES)
      .map(([id, { names }]) => `  (${sql(id)}, ${sql(names.ko)}, ${sql(names.en)})`)
      .join(',\n') + ';',
    '',
    'insert into public.pokedex_entries (dex, number, species_id, is_default, ko_description, en_description) values',
    entries
      .map(
        (e) =>
          `  (${sql(e.dex)}, ${e.number}, ${e.row.id}, true, ${sql(e.description.ko)}, ${sql(e.description.en)})`,
      )
      .join(',\n') + ';',
    '',
  ]
  await writeFile(MIGRATION, out.join('\n'))

  console.log(
    `${rows.length} forms, ${entries.length} entries, ${typeIds.length} types, ${sprites.length} sprites`,
  )
}

await main()
