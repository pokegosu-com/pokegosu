import { notFound, permanentRedirect } from 'next/navigation'

import { ko, pokedex } from '@/lib/pokedex'

import { DexGrid } from './grid'

// The pokedex changes with a deploy, which starts the edge's cache afresh; a
// day is only a fallback.
export const revalidate = 86400

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
  const [{ data, error }, kind, types] = await Promise.all([
    db
      .from('pokedex_entries')
      .select(
        'number, species:pokedex_species(ko_name, en_name, type1, type2, front:sprites->>front)',
      )
      .eq('dex', dex)
      .eq('is_default', true)
      .order('number'),
    db.from('pokedex_kinds').select('ko_name, en_name').eq('id', dex).maybeSingle(),
    db.from('pokedex_types').select('id, ko_name, en_name'),
  ])
  if (error) throw error
  if (kind.error) throw kind.error
  if (types.error) throw types.error
  if (!kind.data) notFound()

  return (
    <main className="max-w-wide mx-auto flex w-full flex-1 flex-col gap-5 px-6 py-8">
      <h1 className="sr-only">{ko(kind.data)}</h1>
      <DexGrid
        dex={dex}
        rows={data.map(({ number, species: s }) => ({
          number,
          name: ko(s),
          types: [s.type1, s.type2].filter((t): t is string => !!t),
          sprite: s.front ?? undefined,
        }))}
        types={types.data.sort((a, b) => typeRank(a.id) - typeRank(b.id)).map((t) => [t.id, ko(t)])}
      />
    </main>
  )
}
