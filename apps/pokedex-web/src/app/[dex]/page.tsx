import Link from 'next/link'
import { notFound, permanentRedirect } from 'next/navigation'

import { dexNo, ko, pokedex, typeNames } from '@/lib/pokedex'

export default async function Pokedex({ params }: PageProps<'/[dex]'>) {
  const { dex } = await params
  // Entries used to live at /25, which meant the national number.
  if (/^\d+$/.test(dex)) permanentRedirect(`/national/${dex}`)

  const [{ data, error }, kind, types] = await Promise.all([
    pokedex()
      .from('pokedex_entries')
      .select('number, species:pokedex_species(ko_name, en_name, type1, type2, sprites)')
      .eq('dex', dex)
      .eq('is_default', true)
      .order('number'),
    pokedex().from('pokedex_kinds').select('id, ko_name, en_name').eq('id', dex).maybeSingle(),
    typeNames(),
  ])
  if (error) throw error
  if (kind.error) throw kind.error
  if (!kind.data) notFound()

  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-8 px-6 py-12">
      <h1 className="text-2xl font-semibold tracking-tight">{ko(kind.data)}</h1>
      <ol className="grid grid-cols-3 gap-3 sm:grid-cols-5">
        {data.map(({ number, species: s }) => {
          const sprites = s.sprites as { animated?: string }
          return (
            <li key={number}>
              <Link
                href={`/${dex}/${number}`}
                className="border-muted/20 hover:border-muted flex flex-col items-center gap-1 rounded-lg border px-2 py-3 text-xs"
              >
                <span className="flex h-16 items-end">
                  {sprites.animated && (
                    // eslint-disable-next-line @next/next/no-img-element -- animated GIFs, served as they are
                    <img src={sprites.animated} alt="" />
                  )}
                </span>
                <span className="text-muted tabular-nums">{dexNo(number)}</span>
                <span className="font-medium">{ko(s)}</span>
                <span className="text-muted">
                  {[s.type1, s.type2]
                    .filter(Boolean)
                    .map((t) => types.get(t!))
                    .join(' · ')}
                </span>
              </Link>
            </li>
          )
        })}
      </ol>
    </main>
  )
}
