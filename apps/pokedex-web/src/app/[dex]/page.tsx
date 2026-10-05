import { notFound, permanentRedirect } from 'next/navigation'

import { every, ko, pokedex } from '@/lib/pokedex'

import { DexGrid } from './grid'

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

/** Every pokedex, each built as a file. */
export async function generateStaticParams() {
  const { data, error } = await pokedex().from('pokedex_kinds').select('id')
  if (error) throw error
  return data.map(({ id }) => ({ dex: id }))
}

export default async function Pokedex({ params }: PageProps<'/[dex]'>) {
  const { dex } = await params
  // Entries used to live at /25, which meant the national number. No file is
  // built for one, so the Worker answers it.
  if (/^\d+$/.test(dex)) permanentRedirect(`/national/${dex}`)

  const db = pokedex()
  const [data, kind, types] = await Promise.all([
    every((from, to) =>
      db
        .from('pokedex_entries')
        .select(
          'number, species:pokedex_species(id, form_of, ko_name, en_name, type1, type2, front:sprites->>front, front_shiny:sprites->>front_shiny)',
        )
        .eq('dex', dex)
        .eq('is_default', true)
        .order('number')
        .range(from, to),
    ),
    db.from('pokedex_kinds').select('ko_name, en_name').eq('id', dex).maybeSingle(),
    db.from('pokedex_types').select('id, ko_name, en_name'),
  ])
  if (kind.error) throw kind.error
  if (types.error) throw types.error
  if (!kind.data) notFound()

  return (
    <main className="max-w-wide mx-auto flex w-full flex-1 flex-col gap-5 px-4 sm:px-6 py-8">
      <h1 className="sr-only">{ko(kind.data)}</h1>
      <DexGrid
        dex={dex}
        rows={data.map(({ number, species: s }) => ({
          id: s.id,
          speciesId: s.form_of ?? s.id,
          number,
          name: ko(s),
          types: [s.type1, s.type2].filter((t): t is string => !!t),
          sprite: s.front ?? undefined,
          shinySprite: s.front_shiny ?? undefined,
        }))}
        types={types.data.sort((a, b) => typeRank(a.id) - typeRank(b.id)).map((t) => [t.id, ko(t)])}
      />
    </main>
  )
}
