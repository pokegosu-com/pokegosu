import Link from 'next/link'
import { notFound } from 'next/navigation'

import { LANGUAGES, dexNo, ko, pokedex, typeNames, type Names } from '@/lib/pokedex'

type Evolution = {
  trigger: string
  min_level?: number
  min_happiness?: number
  time_of_day?: string
  item?: { id: string; names: Names }
  held_item?: { id: string; names: Names }
}

/** What an evolution takes, as a sentence. */
function takes(e: Evolution): string {
  const parts: string[] = []
  if (e.trigger === 'level-up') parts.push(e.min_level ? `Lv.${e.min_level}` : '레벨업')
  if (e.trigger === 'use-item' && e.item) parts.push(`${ko(e.item.names)} 사용`)
  if (e.trigger === 'trade') parts.push('통신교환')
  if (e.held_item) parts.push(`${ko(e.held_item.names)} 지닌 채`)
  if (e.min_happiness) parts.push('친밀도')
  if (e.time_of_day) parts.push(e.time_of_day === 'day' ? '낮' : '밤')
  return parts.join(', ') || e.trigger
}

function gender(rate: number): string {
  if (rate < 0) return '성별 없음'
  const female = (rate / 8) * 100
  return `♂ ${100 - female}% · ♀ ${female}%`
}

const STATS = [
  ['hp', 'HP'],
  ['attack', '공격'],
  ['defense', '방어'],
  ['special_attack', '특수공격'],
  ['special_defense', '특수방어'],
  ['speed', '스피드'],
] as const

export default async function Entry({ params }: PageProps<'/[dexNo]'>) {
  const n = Number((await params).dexNo)
  if (!Number.isInteger(n) || n < 1) notFound()

  const [{ data: forms, error }, types] = await Promise.all([
    pokedex().from('pokedex').select('*').eq('dex_no', n).order('is_default', { ascending: false }),
    typeNames(),
  ])
  if (error) throw error
  const p = forms[0]
  if (!p) notFound()

  const { data: family, error: familyError } = await pokedex()
    .from('pokedex')
    .select('id, dex_no, names, sprites, evolves_from_id, evolution')
    .eq('evolution_chain_id', p.evolution_chain_id)
    .order('dex_no')
  if (familyError) throw familyError
  const byId = new Map(family.map((f) => [f.id, f]))

  const names = p.names as Names
  const sprites = p.sprites as { animated?: string; animated_shiny?: string }

  return (
    <main className="mx-auto flex w-full max-w-3xl flex-1 flex-col gap-8 px-6 py-12">
      <nav className="text-muted text-sm">
        <Link href="/" className="hover:text-ink">
          ← 목록
        </Link>
      </nav>

      <header className="flex items-center gap-6">
        <span className="flex items-end gap-2">
          {sprites.animated && (
            // eslint-disable-next-line @next/next/no-img-element -- animated GIFs, served as they are
            <img src={sprites.animated} alt={ko(names)} className="h-24 w-24 object-contain" />
          )}
          {sprites.animated_shiny && (
            // eslint-disable-next-line @next/next/no-img-element -- animated GIFs, served as they are
            <img
              src={sprites.animated_shiny}
              alt={`${ko(names)} (색이 다른)`}
              className="h-24 w-24 object-contain"
            />
          )}
        </span>
        <div className="space-y-1">
          <p className="text-muted text-sm tabular-nums">{dexNo(p.dex_no)}</p>
          <h1 className="text-3xl font-semibold tracking-tight">{ko(names)}</h1>
          <p className="text-muted text-sm">{ko(p.genera)}</p>
          <p className="flex gap-1 text-xs">
            {[p.type1, p.type2].filter(Boolean).map((t) => (
              <span key={t} className="border-muted/30 rounded border px-1.5 py-0.5">
                {types.get(t!)}
              </span>
            ))}
          </p>
        </div>
      </header>

      {ko(p.descriptions) && <p className="leading-relaxed">{ko(p.descriptions)}</p>}

      <section className="grid gap-8 sm:grid-cols-2">
        <dl className="grid grid-cols-[auto_1fr] gap-x-4 gap-y-2 text-sm">
          <dt className="text-muted">키</dt>
          <dd className="tabular-nums">{(p.height / 10).toFixed(1)} m</dd>
          <dt className="text-muted">몸무게</dt>
          <dd className="tabular-nums">{(p.weight / 10).toFixed(1)} kg</dd>
          <dt className="text-muted">성비</dt>
          <dd className="tabular-nums">{gender(p.gender_rate)}</dd>
          <dt className="text-muted">포획률</dt>
          <dd className="tabular-nums">{p.capture_rate}</dd>
          <dt className="text-muted">부화</dt>
          <dd className="tabular-nums">{p.hatch_counter} 사이클</dd>
        </dl>

        <dl className="grid grid-cols-[auto_2rem_1fr] items-center gap-x-3 gap-y-2 text-sm">
          {STATS.map(([key, label]) => (
            <div key={key} className="contents">
              <dt className="text-muted">{label}</dt>
              <dd className="text-right tabular-nums">{p[key]}</dd>
              <dd className="bg-muted/15 h-1.5 overflow-hidden rounded-full">
                <span
                  className="bg-accent block h-full rounded-full"
                  style={{ width: `${Math.min(100, (p[key] / 180) * 100)}%` }}
                />
              </dd>
            </div>
          ))}
        </dl>
      </section>

      {family.length > 1 && (
        <section className="space-y-3">
          <h2 className="text-muted text-sm font-medium">진화</h2>
          <ol className="flex flex-wrap items-center gap-3 text-sm">
            {family.map((f) => {
              const from = f.evolves_from_id ? byId.get(f.evolves_from_id) : undefined
              const art = (f.sprites as { animated?: string }).animated
              return (
                <li key={f.id} className="flex items-center gap-3">
                  {from && (
                    <span className="text-muted text-xs">→ {takes(f.evolution as Evolution)}</span>
                  )}
                  <Link
                    href={`/${f.dex_no}`}
                    className={`flex flex-col items-center rounded-lg border px-3 py-2 ${f.dex_no === n ? 'border-accent' : 'border-muted/20 hover:border-muted'}`}
                  >
                    {art && (
                      // eslint-disable-next-line @next/next/no-img-element -- animated GIFs, served as they are
                      <img src={art} alt="" className="h-12 w-12 object-contain" />
                    )}
                    <span>{ko(f.names)}</span>
                  </Link>
                </li>
              )
            })}
          </ol>
        </section>
      )}

      {forms.length > 1 && (
        <section className="space-y-3">
          <h2 className="text-muted text-sm font-medium">모습</h2>
          <ul className="flex flex-wrap gap-2 text-sm">
            {forms.map((f) => (
              <li key={f.id} className="border-muted/20 rounded border px-2 py-1">
                {ko(f.names)}
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="space-y-3">
        <h2 className="text-muted text-sm font-medium">다른 언어</h2>
        <dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-1 text-sm">
          {LANGUAGES.filter(([key]) => names[key]).map(([key, label]) => (
            <div key={key} className="contents">
              <dt className="text-muted">{label}</dt>
              <dd lang={key}>{names[key]}</dd>
            </div>
          ))}
        </dl>
      </section>
    </main>
  )
}
