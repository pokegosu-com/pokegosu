import Link from 'next/link'
import { notFound, permanentRedirect } from 'next/navigation'

import { ko, pokedex } from '@/lib/pokedex'

import { DexGrid } from './grid'

/** The pokedexes, in the order the tabs show them: national first, then by generation. */
const DEXES = ['national', 'kanto', 'johto', 'hoenn']

/** The games' order of types, which the table does not keep. */
const TYPE_ORDER = [
  'normal',
  'fire',
  'water',
  'electric',
  'grass',
  'ice',
  'fighting',
  'poison',
  'ground',
  'flying',
  'psychic',
  'bug',
  'rock',
  'ghost',
  'dragon',
  'dark',
  'steel',
  'fairy',
]
const typeRank = (id: string) => TYPE_ORDER.indexOf(id) + 1 || TYPE_ORDER.length + 1

export default async function Pokedex({ params }: PageProps<'/[dex]'>) {
  const { dex } = await params
  // Entries used to live at /25, which meant the national number.
  if (/^\d+$/.test(dex)) permanentRedirect(`/national/${dex}`)

  const db = pokedex()
  const [{ data, error }, kinds, types] = await Promise.all([
    db
      .from('pokedex_entries')
      .select('number, species:pokedex_species(ko_name, en_name, type1, type2, sprites)')
      .eq('dex', dex)
      .eq('is_default', true)
      .order('number'),
    db.from('pokedex_kinds').select('id, ko_name, en_name'),
    db.from('pokedex_types').select('id, ko_name, en_name'),
  ])
  if (error) throw error
  if (kinds.error) throw kinds.error
  if (types.error) throw types.error
  const kind = kinds.data.find((k) => k.id === dex)
  if (!kind) notFound()

  return (
    <main className="max-w-wide mx-auto flex w-full flex-1 flex-col gap-5 px-6 py-8">
      <h1 className="sr-only">{ko(kind)}</h1>
      <nav aria-label="도감" className="border-line flex gap-6 border-b">
        {DEXES.filter((id) => kinds.data.some((k) => k.id === id)).map((id) => (
          <Link
            key={id}
            href={`/${id}`}
            aria-current={id === dex ? 'page' : undefined}
            className="text-muted aria-[current=page]:border-ink aria-[current=page]:text-ink -mb-px border-b-2 border-transparent py-2.5 text-sm font-medium"
          >
            {ko(kinds.data.find((k) => k.id === id)!)}
          </Link>
        ))}
      </nav>
      <DexGrid
        dex={dex}
        rows={data.map(({ number, species: s }) => ({
          number,
          name: ko(s),
          types: [s.type1, s.type2].filter((t): t is string => !!t),
          sprite: (s.sprites as { front?: string }).front,
        }))}
        types={types.data.sort((a, b) => typeRank(a.id) - typeRank(b.id)).map((t) => [t.id, ko(t)])}
      />
    </main>
  )
}
