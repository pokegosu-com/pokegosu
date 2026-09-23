import Link from 'next/link'

import { dexNo, ko, pokedex, typeNames } from '@/lib/pokedex'

export default async function Pokedex() {
  const [{ data, error }, types] = await Promise.all([
    pokedex()
      .from('pokedex')
      .select('dex_no, names, type1, type2, sprites')
      .eq('is_default', true)
      .order('dex_no'),
    typeNames(),
  ])
  if (error) throw error

  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-8 px-6 py-12">
      <h1 className="text-2xl font-semibold tracking-tight">pokedex</h1>
      <ol className="grid grid-cols-3 gap-3 sm:grid-cols-5">
        {data.map((p) => {
          const sprites = p.sprites as { animated?: string }
          return (
            <li key={p.dex_no}>
              <Link
                href={`/${p.dex_no}`}
                className="border-muted/20 hover:border-muted flex flex-col items-center gap-1 rounded-lg border px-2 py-3 text-xs"
              >
                <span className="flex h-16 items-end">
                  {sprites.animated && (
                    // eslint-disable-next-line @next/next/no-img-element -- animated GIFs, served as they are
                    <img src={sprites.animated} alt="" />
                  )}
                </span>
                <span className="text-muted tabular-nums">{dexNo(p.dex_no)}</span>
                <span className="font-medium">{ko(p.names)}</span>
                <span className="text-muted">
                  {[p.type1, p.type2]
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
