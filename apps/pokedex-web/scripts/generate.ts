// Reads PokéAPI once and writes what the rest of the repository needs from it:
// the sprite manifest this app serves from, and the migration that fills the
// pokedex tables. Both are committed; nothing reads PokéAPI at build or run
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

/** Generation I: national dex numbers 1 to 151, in their default forms. */
const LAST_DEX_NO = 151

/**
 * The languages kept, as the pokedex keys them, and PokéAPI's codes for each
 * in order of preference. PokéAPI's "ja" is written as an adult reads it, with
 * kanji; "ja-hrkt" is the all-kana text the games offer children.
 */
const LANGUAGES: Record<string, string[]> = {
  ko: ['ko'],
  en: ['en'],
  ja: ['ja', 'ja-hrkt'],
  'zh-Hans': ['zh-hans'],
  'zh-Hant': ['zh-hant'],
  fr: ['fr'],
  de: ['de'],
  es: ['es'],
  it: ['it'],
}

/** Scripts written without spaces between words, so a line break joins with nothing. */
const UNSPACED = new Set(['ja', 'zh-Hans', 'zh-Hant'])

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

/** One value per kept language, from whichever PokéAPI code it prefers. */
function localise<T extends Localised>(
  entries: T[],
  value: (entry: T) => string,
  pick: (matching: T[]) => T | undefined = (matching) => matching[0],
): Record<string, string> {
  const out: Record<string, string> = {}
  for (const [key, codes] of Object.entries(LANGUAGES)) {
    for (const code of codes) {
      const chosen = pick(entries.filter((e) => e.language.name === code))
      if (chosen) {
        out[key] = value(chosen)
        break
      }
    }
  }
  return out
}

/** PokéAPI keeps the games' line breaks and page breaks; a screen wants prose. */
function prose(text: string, key: string): string {
  const joiner = UNSPACED.has(key) ? '' : ' '
  return text
    .replace(/­\n/g, '')
    .replace(/[\n\f\r]+/g, joiner)
    .replace(/ {2,}/g, ' ')
    .trim()
}

const itemNames = new Map<string, Record<string, string>>()

/** How a form is reached, with only what the games actually ask for. */
async function evolutionOf(detail: EvolutionDetail) {
  const out: Record<string, unknown> = { trigger: detail.trigger.name }
  if (detail.min_level) out.min_level = detail.min_level
  if (detail.min_happiness) out.min_happiness = detail.min_happiness
  if (detail.time_of_day) out.time_of_day = detail.time_of_day
  for (const key of ['item', 'held_item'] as const) {
    const item = detail[key]
    if (!item) continue
    if (!itemNames.has(item.name)) {
      const fetched = await get<{ names: ({ name: string } & Localised)[] }>(`item/${item.name}`)
      itemNames.set(
        item.name,
        localise(fetched.names, (n) => n.name),
      )
    }
    out[key] = { id: item.name, names: itemNames.get(item.name) }
  }
  return out
}

type Row = {
  id: number
  slug: string
  dexNo: number
  generation: number
  names: Record<string, string>
  genera: Record<string, string>
  descriptions: Record<string, string>
  types: string[]
  stats: Record<string, number>
  height: number
  weight: number
  growthRate: string
  captureRate: number
  hatchCounter: number
  genderRate: number
  isBaby: boolean
  isLegendary: boolean
  isMythical: boolean
  chainId: number
  evolvesFrom: number | null
  evolution: Record<string, unknown> | null
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
      genera: localise(s.genera, (g) => g.genus),
      // The newest entry in each language: PokéAPI lists them oldest first.
      descriptions: Object.fromEntries(
        Object.entries(
          localise(
            s.flavor_text_entries,
            (f) => f.flavor_text,
            (matching) => matching.at(-1),
          ),
        ).map(([key, text]) => [key, prose(text, key)]),
      ),
      types: pokemon.types.sort((a, b) => a.slot - b.slot).map((t) => t.type.name),
      stats: Object.fromEntries(pokemon.stats.map((st) => [STATS[st.stat.name], st.base_stat])),
      height: pokemon.height,
      weight: pokemon.weight,
      growthRate: s.growth_rate.name,
      captureRate: s.capture_rate,
      hatchCounter: s.hatch_counter,
      genderRate: s.gender_rate,
      isBaby: s.is_baby,
      isLegendary: s.is_legendary,
      isMythical: s.is_mythical,
      chainId: idOf(s.evolution_chain),
      evolvesFrom: evolution ? evolution.from : null,
      evolution: evolution ? await evolutionOf(evolution.detail) : null,
      sprites: {
        animated: `/sprites/pokemon/${s.id}.gif`,
        animated_shiny: `/sprites/pokemon/shiny/${s.id}.gif`,
      },
    })
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
    JSON.stringify({ commit: SPRITES_COMMIT, files: sprites }, null, 2) + '\n',
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
    `-- ${rows.length} forms: the default form of every Generation I species.`,
    '',
    'insert into public.pokedex_types (id, names) values',
    typeIds.map((id) => `  (${sql(id)}, ${sql(typeNames.get(id))})`).join(',\n') + ';',
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
    'insert into public.pokedex (',
    '  id, slug, dex_no, is_default, generation, names, genera, descriptions,',
    '  type1, type2, hp, attack, defense, special_attack, special_defense, speed, height, weight,',
    '  growth_rate, capture_rate, hatch_counter, gender_rate, is_baby, is_legendary, is_mythical,',
    '  evolution_chain_id, evolves_from_id, evolution, sprites',
    ') values',
    ordered
      .map((r) =>
        [
          `  (${r.id}, ${sql(r.slug)}, ${r.dexNo}, true, ${r.generation},`,
          `   ${sql(r.names)},`,
          `   ${sql(r.genera)},`,
          `   ${sql(r.descriptions)},`,
          `   ${sql(r.types[0])}, ${sql(r.types[1] ?? null)}, ${r.stats.hp}, ${r.stats.attack}, ${r.stats.defense},` +
            ` ${r.stats.special_attack}, ${r.stats.special_defense}, ${r.stats.speed}, ${r.height}, ${r.weight},`,
          `   ${sql(r.growthRate)}, ${r.captureRate}, ${r.hatchCounter}, ${r.genderRate}, ${r.isBaby}, ${r.isLegendary}, ${r.isMythical},`,
          `   ${r.chainId}, ${sql(r.evolvesFrom)}, ${sql(r.evolution)}, ${sql(r.sprites)})`,
        ].join('\n'),
      )
      .join(',\n') + ';',
    '',
  ]
  await writeFile(MIGRATION, out.join('\n'))

  console.log(`${rows.length} forms, ${typeIds.length} types, ${sprites.length} sprites`)
}

await main()
