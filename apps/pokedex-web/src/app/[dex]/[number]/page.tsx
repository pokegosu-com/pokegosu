import Link from 'next/link'
import { notFound } from 'next/navigation'

import { ProgressBar, TypeChip } from '@pokegosu/ui/pokemon'

import { dexNo, ko, type Named, pokedex, typeNames } from '@/lib/pokedex'

import { Sprite } from './sprite'

type Method = {
  trigger: string
  level: number | null
  item: string | null
  held_item: string | null
  min_happiness: number | null
  time_of_day: string | null
  relative_physical_stats: number | null
  min_beauty: number | null
  chance: number | null
  gender: string | null
  known_move: string | null
  location: string | null
  party: Named | null
}

const PHYSICAL_STATS: Record<number, string> = {
  1: '공격 > 방어',
  0: '공격 = 방어',
  [-1]: '공격 < 방어',
}

/**
 * What an evolution takes, as a phrase: "Lv.16", "천둥의돌 사용", "친밀도 · 밤",
 * "금속코트 지닌 채 통신교환", "Lv.7 · 성격값 50%", "Lv.20 · ♀",
 * "구르기 배운 채 레벨업", "천관산에서 레벨업", "레벨업 · 동료 총어".
 */
function takes(method: Method | undefined, names: Map<string, string>): string {
  if (!method) return ''
  const parts: string[] = []
  if (method.item) parts.push(`${names.get(method.item)} 사용`)
  else if (method.held_item)
    parts.push(`${names.get(method.held_item)} 지닌 채 ${names.get(method.trigger)}`)
  else if (method.trigger === 'level-up' && method.level) parts.push(`Lv.${method.level}`)
  else if (method.known_move)
    parts.push(`${names.get(method.known_move)} 배운 채 ${names.get(method.trigger)}`)
  else if (method.location)
    parts.push(`${names.get(method.location)}에서 ${names.get(method.trigger)}`)
  else if (method.party) parts.push(`${names.get(method.trigger)} · 동료 ${ko(method.party)}`)
  // Without the number: the games ask 220 up to Generation VII and 160 since,
  // the same for every species in a game, and PokéAPI mixes the two.
  if (method.min_happiness) parts.push('친밀도')
  if (method.time_of_day) parts.push(method.time_of_day === 'day' ? '낮' : '밤')
  if (method.relative_physical_stats !== null)
    parts.push(PHYSICAL_STATS[method.relative_physical_stats])
  if (method.min_beauty) parts.push('아름다움')
  // Which half is fixed for each Pokémon, by its personality value.
  if (method.chance) parts.push(`성격값 ${method.chance}%`)
  if (method.gender) parts.push(method.gender === 'female' ? '♀' : '♂')
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

export default async function Entry({ params }: PageProps<'/[dex]/[number]'>) {
  const { dex, number } = await params
  const n = Number(number)
  if (!Number.isInteger(n) || n < 1) notFound()

  const db = pokedex()
  const [forms, all, around, kinds, triggers, items, moves, locations, methods, types] =
    await Promise.all([
      db
        .from('pokedex_entries')
        .select('is_default, species:pokedex_species(*)')
        .eq('dex', dex)
        .eq('number', n)
        .order('is_default', { ascending: false }),
      // Every form in this pokedex, small enough to take whole: the family is
      // found by following evolves_from_id, and each links by its number here.
      // A stage this pokedex does not list is left out: Kanto's has no Pichu.
      db
        .from('pokedex_entries')
        .select(
          'number, species:pokedex_species(id, ko_name, en_name, sprites, evolves_from_id, evolution_method)',
        )
        .eq('dex', dex),
      // The numbers either side, in the same pokedex.
      db
        .from('pokedex_entries')
        .select('number, species:pokedex_species(ko_name, en_name)')
        .eq('dex', dex)
        .eq('is_default', true)
        .in('number', [n - 1, n + 1])
        .order('number'),
      db.from('pokedex_kinds').select('id, ko_name, en_name'),
      db.from('pokedex_evolution_triggers').select('id, ko_name, en_name'),
      db.from('pokedex_items').select('id, ko_name, en_name'),
      db.from('pokedex_moves').select('id, ko_name, en_name'),
      db.from('pokedex_locations').select('id, ko_name, en_name'),
      db
        .from('pokedex_evolution_methods')
        .select(
          'id, trigger, level, item, held_item, min_happiness, time_of_day, relative_physical_stats, min_beauty, chance, gender, known_move, location, party:pokedex_species!party_species_id(ko_name, en_name)',
        ),
      typeNames(),
    ])
  for (const result of [forms, all, around, kinds, triggers, items, moves, locations, methods]) {
    if (result.error) throw result.error
  }
  const kindNames = new Map(kinds.data!.map((k) => [k.id, ko(k)]))
  const dexName = kindNames.get(dex)
  if (!dexName) notFound()
  const p = forms.data?.[0]?.species
  if (!p) notFound()

  // This pokedex's entry for the form shown; each pokedex writes its own.
  const entriesOf = await db
    .from('pokedex_entries')
    .select('dex, number, ko_description, en_description')
    .eq('species_id', p.id)
    .eq('dex', dex)
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
  const evolutionNames = new Map(
    [...triggers.data!, ...items.data!, ...moves.data!, ...locations.data!].map((t) => [
      t.id,
      ko(t),
    ]),
  )
  const methodOf = new Map(methods.data!.map((m) => [m.id, m]))
  const entries = entriesOf.data!.filter((e) => e.ko_description || e.en_description)
  const sprites = p.sprites as { artwork?: string; artwork_shiny?: string }
  const previous = around.data!.find((e) => e.number === n - 1)
  const next = around.data!.find((e) => e.number === n + 1)

  const statTotal = STATS.reduce((sum, [key]) => sum + p[key], 0)

  return (
    <main className="max-w-wide mx-auto flex w-full flex-1 flex-col gap-8 px-6 py-8">
      <nav className="text-muted flex justify-between gap-4 text-sm">
        <Link href={`/${dex}`} className="hover:text-ink">
          ← {dexName}
        </Link>
        <span className="flex gap-5">
          {previous && (
            <Link href={`/${dex}/${previous.number}`} className="hover:text-ink">
              <span className="font-mono text-xs">{dexNo(previous.number)}</span>{' '}
              {ko(previous.species)}
            </Link>
          )}
          {next && (
            <Link href={`/${dex}/${next.number}`} className="hover:text-ink">
              {ko(next.species)} <span className="font-mono text-xs">{dexNo(next.number)}</span> →
            </Link>
          )}
        </span>
      </nav>

      <header className="flex items-center gap-8">
        <Sprite name={ko(p)} normal={sprites.artwork} shiny={sprites.artwork_shiny} />
        <div className="flex flex-col gap-2">
          <p className="text-muted font-mono text-xs tabular-nums">
            {dexName} {dexNo(n)}
          </p>
          <h1 className="text-3xl font-semibold tracking-tight">{ko(p)}</h1>
          <p className="text-muted text-sm">
            {p.ko_genus ?? p.en_genus}
            {p.category && ` · ${CATEGORIES[p.category]}`}
          </p>
          <p className="flex gap-1">
            {[p.type1, p.type2]
              .filter((t): t is string => !!t)
              .map((t) => (
                <TypeChip key={t} id={t} name={types.get(t) ?? t} />
              ))}
          </p>
          {entries.map((e) => (
            <p key={e.dex} className="mt-2 max-w-xl leading-relaxed">
              {e.ko_description ?? e.en_description}
            </p>
          ))}
        </div>
      </header>

      <section className="grid gap-10 sm:grid-cols-2">
        <div className="space-y-3">
          <h2 className="text-muted text-sm font-medium">정보</h2>
          <dl className="grid grid-cols-[4.5rem_minmax(0,1fr)] gap-y-2 text-sm">
            <dt className="text-muted">키</dt>
            <dd className="font-mono text-[13px]">{(p.height / 10).toFixed(1)} m</dd>
            <dt className="text-muted">몸무게</dt>
            <dd className="font-mono text-[13px]">{(p.weight / 10).toFixed(1)} kg</dd>
            <dt className="text-muted">성비</dt>
            <dd className="font-mono text-[13px]">{gender(p.gender_rate)}</dd>
            <dt className="text-muted">포획률</dt>
            <dd className="font-mono text-[13px]">{p.capture_rate}</dd>
            <dt className="text-muted">부화</dt>
            <dd className="font-mono text-[13px]">{p.hatch_counter} 사이클</dd>
            <dt className="text-muted">첫 등장</dt>
            <dd className="font-mono text-[13px]">{p.generation}세대</dd>
          </dl>
        </div>
        <div className="space-y-3">
          <h2 className="text-muted text-sm font-medium">종족값</h2>
          <dl className="grid grid-cols-[4rem_2rem_minmax(0,1fr)] items-center gap-x-3 gap-y-2 text-sm">
            {STATS.map(([key, label]) => (
              <div key={key} className="contents">
                <dt className="text-muted">{label}</dt>
                <dd className="text-right font-mono text-[13px]">{p[key]}</dd>
                <dd>
                  <ProgressBar value={p[key]} max={180} label={label} />
                </dd>
              </div>
            ))}
            <dt className="text-muted border-line border-t pt-2">합계</dt>
            <dd className="border-line border-t pt-2 text-right font-mono text-[13px] font-medium">
              {statTotal}
            </dd>
            <dd className="border-line h-full border-t" />
          </dl>
        </div>
      </section>

      {family.length > 1 && (
        <section className="space-y-3">
          <h2 className="text-muted text-sm font-medium">진화</h2>
          <ol className="flex flex-wrap items-center gap-3">
            {family.map((f, i) => {
              const art = (f.sprites as { front?: string }).front
              return (
                <li key={f.id} className="flex items-center gap-3">
                  {/* The first stage shown has nothing before it here, even
                      where it evolves from one this pokedex leaves out. */}
                  {i > 0 && f.evolution_method && (
                    <span className="text-muted text-xs">
                      → {takes(methodOf.get(f.evolution_method), evolutionNames)}
                    </span>
                  )}
                  <Link
                    href={`/${dex}/${f.number}`}
                    aria-current={f.number === n ? 'page' : undefined}
                    className="border-line hover:border-line-strong aria-[current=page]:border-accent flex flex-col items-center gap-1 rounded-lg border px-3 py-2 text-[13px]"
                  >
                    <span className="bg-surface-raised grid size-24 place-items-center rounded-md">
                      {art && (
                        // eslint-disable-next-line @next/next/no-img-element -- pixel sprites, served as they are
                        <img src={art} alt="" className="size-24 [image-rendering:pixelated]" />
                      )}
                    </span>
                    {ko(f)}
                    <span className="text-muted font-mono text-[11px]">{dexNo(f.number)}</span>
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
              <li key={f.id} className="border-line rounded border px-2 py-1">
                {ko(f)}
              </li>
            ))}
          </ul>
        </section>
      )}
    </main>
  )
}
