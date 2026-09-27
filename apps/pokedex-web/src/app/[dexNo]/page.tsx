import Link from 'next/link'
import { notFound } from 'next/navigation'

import { dexNo, ko, pokedex, typeNames } from '@/lib/pokedex'

type Method = {
  trigger: string
  level: number | null
  item: string | null
  held_item: string | null
  min_happiness: number | null
  time_of_day: string | null
  relative_physical_stats: number | null
}

const PHYSICAL_STATS: Record<number, string> = {
  1: '공격 > 방어',
  0: '공격 = 방어',
  [-1]: '공격 < 방어',
}

/**
 * What an evolution takes, as a phrase: "Lv.16", "천둥의돌 사용", "친밀도 160 · 밤",
 * "금속코트 지닌 채 통신교환".
 */
function takes(method: Method | undefined, names: Map<string, string>): string {
  if (!method) return ''
  const parts: string[] = []
  if (method.item) parts.push(`${names.get(method.item)} 사용`)
  else if (method.held_item)
    parts.push(`${names.get(method.held_item)} 지닌 채 ${names.get(method.trigger)}`)
  else if (method.trigger === 'level-up' && method.level) parts.push(`Lv.${method.level}`)
  if (method.min_happiness) parts.push(`친밀도 ${method.min_happiness}`)
  if (method.time_of_day) parts.push(method.time_of_day === 'day' ? '낮' : '밤')
  if (method.relative_physical_stats !== null)
    parts.push(PHYSICAL_STATS[method.relative_physical_stats])
  return parts.join(' · ') || (names.get(method.trigger) ?? '')
}

function gender(rate: number): string {
  if (rate < 0) return '성별 없음'
  const female = (rate / 8) * 100
  return `♂ ${100 - female}% · ♀ ${female}%`
}

const CATEGORIES: Record<string, string> = { baby: '아기', legendary: '전설', mythical: '환상' }

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

  const db = pokedex()
  const [forms, all, kinds, triggers, items, methods, types] = await Promise.all([
    db
      .from('pokedex_entries')
      .select('is_default, species:pokedex_species(*)')
      .eq('dex', 'national')
      .eq('number', n)
      .order('is_default', { ascending: false }),
    // Every form, small enough to take whole: the family is found by following
    // evolves_from_id, and each links by its national number.
    db
      .from('pokedex_entries')
      .select(
        'number, species:pokedex_species(id, ko_name, en_name, sprites, evolves_from_id, evolution_method)',
      )
      .eq('dex', 'national'),
    db.from('pokedex_kinds').select('id, ko_name, en_name'),
    db.from('pokedex_evolution_triggers').select('id, ko_name, en_name'),
    db.from('pokedex_items').select('id, ko_name, en_name'),
    db
      .from('pokedex_evolution_methods')
      .select(
        'id, trigger, level, item, held_item, min_happiness, time_of_day, relative_physical_stats',
      ),
    typeNames(),
  ])
  for (const result of [forms, all, kinds, triggers, items, methods]) {
    if (result.error) throw result.error
  }
  const p = forms.data?.[0]?.species
  if (!p) notFound()

  // Every pokedex's entry for the form shown.
  const entriesOf = await db
    .from('pokedex_entries')
    .select('dex, number, ko_description, en_description')
    .eq('species_id', p.id)
  if (entriesOf.error) throw entriesOf.error

  const rows = new Map(all.data!.map(({ number, species }) => [species.id, { ...species, number }]))
  const firstOf = (id: number): number => {
    const row = rows.get(id)
    return row?.evolves_from_id ? firstOf(row.evolves_from_id) : id
  }
  const stageOf = (id: number): number => {
    const row = rows.get(id)
    return row?.evolves_from_id ? stageOf(row.evolves_from_id) + 1 : 0
  }
  // By stage before number: a baby came in a later generation, so Pichu's
  // number is higher than Raichu's, yet it comes first.
  const family = [...rows.values()]
    .filter((f) => firstOf(f.id) === firstOf(p.id))
    .sort((a, b) => stageOf(a.id) - stageOf(b.id) || a.number - b.number)
  const kindNames = new Map(kinds.data!.map((k) => [k.id, ko(k)]))
  const evolutionNames = new Map([...triggers.data!, ...items.data!].map((t) => [t.id, ko(t)]))
  const methodOf = new Map(methods.data!.map((m) => [m.id, m]))
  const entries = entriesOf.data!.filter((e) => e.ko_description || e.en_description)
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
            <img src={sprites.animated} alt={ko(p)} className="h-24 w-24 object-contain" />
          )}
          {sprites.animated_shiny && (
            // eslint-disable-next-line @next/next/no-img-element -- animated GIFs, served as they are
            <img
              src={sprites.animated_shiny}
              alt={`${ko(p)} (색이 다른)`}
              className="h-24 w-24 object-contain"
            />
          )}
        </span>
        <div className="space-y-1">
          <p className="text-muted text-sm tabular-nums">{dexNo(n)}</p>
          <h1 className="text-3xl font-semibold tracking-tight">{ko(p)}</h1>
          <p className="text-muted text-sm">
            {p.ko_genus ?? p.en_genus}
            {p.category && ` · ${CATEGORIES[p.category]}`}
          </p>
          <p className="flex gap-1 text-xs">
            {[p.type1, p.type2].filter(Boolean).map((t) => (
              <span key={t} className="border-muted/30 rounded border px-1.5 py-0.5">
                {types.get(t!)}
              </span>
            ))}
          </p>
        </div>
      </header>

      <section className="space-y-3">
        {entries
          .sort((a, b) =>
            a.dex === 'national' ? -1 : b.dex === 'national' ? 1 : a.dex.localeCompare(b.dex),
          )
          .map((e) => (
            <div key={e.dex} className="space-y-1">
              <p className="text-muted text-xs">
                {kindNames.get(e.dex)} {dexNo(e.number)}
              </p>
              <p className="leading-relaxed">{e.ko_description ?? e.en_description}</p>
            </div>
          ))}
      </section>

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
          <dt className="text-muted">첫 등장</dt>
          <dd className="tabular-nums">{p.generation}세대</dd>
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
              const art = (f.sprites as { animated?: string }).animated
              return (
                <li key={f.id} className="flex items-center gap-3">
                  {f.evolution_method && (
                    <span className="text-muted text-xs">
                      → {takes(methodOf.get(f.evolution_method), evolutionNames)}
                    </span>
                  )}
                  <Link
                    href={`/${f.number}`}
                    className={`flex flex-col items-center rounded-lg border px-3 py-2 ${f.number === n ? 'border-accent' : 'border-muted/20 hover:border-muted'}`}
                  >
                    {art && (
                      // eslint-disable-next-line @next/next/no-img-element -- animated GIFs, served as they are
                      <img src={art} alt="" className="h-12 w-12 object-contain" />
                    )}
                    <span>{ko(f)}</span>
                  </Link>
                </li>
              )
            })}
          </ol>
        </section>
      )}

      {forms.data!.length > 1 && (
        <section className="space-y-3">
          <h2 className="text-muted text-sm font-medium">모습</h2>
          <ul className="flex flex-wrap gap-2 text-sm">
            {forms.data!.map(({ species: f }) => (
              <li key={f.id} className="border-muted/20 rounded border px-2 py-1">
                {ko(f)}
              </li>
            ))}
          </ul>
        </section>
      )}

      <section className="space-y-3">
        <h2 className="text-muted text-sm font-medium">이름</h2>
        <dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-1 text-sm">
          <dt className="text-muted">한국어</dt>
          <dd lang="ko">{p.ko_name}</dd>
          <dt className="text-muted">English</dt>
          <dd lang="en">{p.en_name}</dd>
        </dl>
      </section>
    </main>
  )
}
