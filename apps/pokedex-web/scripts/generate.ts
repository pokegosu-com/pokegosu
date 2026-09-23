// Reads PokéAPI once and writes what the rest of the repository needs from it:
// the sprite manifest this app serves from, and the migration that loads the
// game's reference data. Both are committed; nothing reads PokéAPI at build
// or run time.
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

/** Generation I: national dex numbers 1 to 151. */
const LAST_SPECIES = 151

const MANIFEST = fileURLToPath(new URL('../sprites.json', import.meta.url))
const MIGRATION = fileURLToPath(
  new URL('../../../supabase/migrations/20260923120001_game_species.sql', import.meta.url),
)

type Named = { name: string; url: string }
type Species = {
  id: number
  name: string
  names: { name: string; language: Named }[]
  capture_rate: number
  hatch_counter: number
  growth_rate: Named
  egg_groups: Named[]
  evolution_chain: { url: string }
}
type ChainLink = {
  species: Named
  evolution_details: { trigger: Named; min_level: number | null }[]
  evolves_to: ChainLink[]
}
type Pokemon = { types: { slot: number; type: Named }[] }
type GrowthRate = { levels: { level: number; experience: number }[] }
type Type = { names: { name: string; language: Named }[] }

async function get<T>(url: string): Promise<T> {
  const response = await fetch(url.startsWith('http') ? url : `https://pokeapi.co/api/v2/${url}`)
  if (!response.ok) throw new Error(`${url}: ${response.status}`)
  return (await response.json()) as T
}

function idOf(resource: Named): number {
  return Number(resource.url.replace(/\/$/, '').split('/').pop())
}

function korean(names: { name: string; language: Named }[]): string {
  const name = names.find((n) => n.language.name === 'ko')?.name
  if (!name) throw new Error(`no Korean name among ${names.map((n) => n.name).join(', ')}`)
  return name
}

/** A level-up evolution with nothing but a level to it, or null. */
function levelOf(link: ChainLink): number | null {
  const detail = link.evolution_details.find((d) => d.trigger.name === 'level-up' && d.min_level)
  return detail?.min_level ?? null
}

type Row = {
  id: number
  slug: string
  name: string
  types: string[]
  growthRate: string
  captureRate: number
  hatchCounter: number
  evolvesFrom: number | null
  evolutionLevel: number | null
  lineId: number
}

/**
 * The lines the game hatches: every step between two Generation I species is a
 * plain level-up. A line with a stone or a trade anywhere in it is left out
 * whole rather than cut short, and so is one with no evolution at all.
 * Evolutions into later generations do not exist yet, so Golbat is Zubat's
 * last form here.
 */
function lines(chains: ChainLink[], species: Map<number, Species>): Row[][] {
  const kept: Row[][] = []
  for (const chain of chains) {
    const root = idOf(chain.species)
    if (root > LAST_SPECIES) continue
    const rows: Row[] = []
    let whole = true
    const walk = (link: ChainLink, from: number | null, level: number | null) => {
      const id = idOf(link.species)
      const s = species.get(id)!
      rows.push({
        id,
        slug: s.name,
        name: korean(s.names),
        types: [],
        growthRate: s.growth_rate.name,
        captureRate: s.capture_rate,
        hatchCounter: s.hatch_counter,
        evolvesFrom: from,
        evolutionLevel: level,
        lineId: root,
      })
      for (const next of link.evolves_to) {
        if (idOf(next.species) > LAST_SPECIES) continue
        const nextLevel = levelOf(next)
        if (nextLevel === null) whole = false
        walk(next, id, nextLevel)
      }
    }
    walk(chain, null, null)
    if (whole && rows.length > 1) kept.push(rows)
  }
  return kept
}

function sqlText(value: string): string {
  return `'${value.replaceAll("'", "''")}'`
}

function sqlOrNull(value: number | string | null): string {
  if (value === null) return 'null'
  return typeof value === 'number' ? String(value) : sqlText(value)
}

async function sha256Of(url: string): Promise<string> {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`${url}: ${response.status}`)
  return createHash('sha256')
    .update(Buffer.from(await response.arrayBuffer()))
    .digest('hex')
}

async function main() {
  const species = new Map<number, Species>()
  await Promise.all(
    Array.from({ length: LAST_SPECIES }, async (_, i) => {
      species.set(i + 1, await get<Species>(`pokemon-species/${i + 1}`))
    }),
  )

  const chainUrls = [...new Set([...species.values()].map((s) => s.evolution_chain.url))]
  const chains = await Promise.all(chainUrls.map((url) => get<{ chain: ChainLink }>(url)))
  const kept = lines(
    chains.map((c) => c.chain),
    species,
  ).sort((a, b) => a[0].id - b[0].id)
  const rows = kept.flat().sort((a, b) => a.id - b.id)

  // Types as they are today: Magnemite is Electric/Steel, not the Electric it
  // was in 1996.
  await Promise.all(
    rows.map(async (row) => {
      const pokemon = await get<Pokemon>(`pokemon/${row.id}`)
      row.types = pokemon.types.sort((a, b) => a.slot - b.slot).map((t) => t.type.name)
    }),
  )
  const typeIds = [...new Set(rows.flatMap((r) => r.types))].sort()
  const typeNames = new Map(
    await Promise.all(
      typeIds.map(async (id) => [id, korean((await get<Type>(`type/${id}`)).names)] as const),
    ),
  )

  const rates = [...new Set(rows.map((r) => r.growthRate))].sort()
  const levels = new Map(
    await Promise.all(
      rates.map(
        async (rate) => [rate, (await get<GrowthRate>(`growth-rate/${rate}`)).levels] as const,
      ),
    ),
  )

  const sprites: { path: string; source: string; sha256: string }[] = []
  const add = async (path: string, source: string) => {
    sprites.push({ path, source, sha256: await sha256Of(source) })
  }
  await add('sprites/egg.png', `${SPRITES_BASE}/egg.png`)
  const animated = `${SPRITES_BASE}/versions/generation-v/black-white/animated`
  for (const row of rows) {
    await add(`sprites/pokemon/${row.id}.gif`, `${animated}/${row.id}.gif`)
    await add(`sprites/pokemon/shiny/${row.id}.gif`, `${animated}/shiny/${row.id}.gif`)
  }

  await writeFile(
    MANIFEST,
    JSON.stringify(
      {
        commit: SPRITES_COMMIT,
        species: rows.map((r) => ({ id: r.id, name: r.name })),
        files: sprites,
      },
      null,
      2,
    ) + '\n',
  )

  const out: string[] = []
  out.push(
    '-- Generated by apps/pokedex-web/scripts/generate.ts from PokéAPI. Do not edit;',
    '-- change the script and run it again.',
    '--',
    `-- ${kept.length} lines, ${rows.length} species: every Generation I line whose`,
    '-- evolutions are all plain level-ups.',
    '',
    'insert into public.pokemon_types (id, name) values',
    typeIds.map((id) => `  (${sqlText(id)}, ${sqlText(typeNames.get(id)!)})`).join(',\n') + ';',
    '',
    'insert into public.growth_rates (id) values',
    rates.map((r) => `  (${sqlText(r)})`).join(',\n') + ';',
    '',
    'insert into public.experience_levels (growth_rate, level, exp) values',
    rates
      .flatMap((rate) =>
        levels
          .get(rate)!
          .sort((a, b) => a.level - b.level)
          .map((l) => `  (${sqlText(rate)}, ${l.level}, ${l.experience})`),
      )
      .join(',\n') + ';',
    '',
    '-- Parents come before children, so evolves_from always finds its row.',
    'insert into public.species',
    '  (id, slug, name, type1, type2, growth_rate, capture_rate, hatch_counter, line_id, evolves_from, evolution_level) values',
    [...rows]
      .sort(
        (a, b) =>
          (a.evolvesFrom === null ? 0 : 1) - (b.evolvesFrom === null ? 0 : 1) || a.id - b.id,
      )
      .map(
        (r) =>
          `  (${r.id}, ${sqlText(r.slug)}, ${sqlText(r.name)}, ${sqlText(r.types[0])}, ${sqlOrNull(r.types[1] ?? null)}, ` +
          `${sqlText(r.growthRate)}, ${r.captureRate}, ${r.hatchCounter}, ${r.lineId}, ` +
          `${sqlOrNull(r.evolvesFrom)}, ${sqlOrNull(r.evolutionLevel)})`,
      )
      .join(',\n') + ';',
    '',
  )
  await writeFile(MIGRATION, out.join('\n'))

  console.log(`${kept.length} lines, ${rows.length} species, ${sprites.length} sprites`)
}

await main()
