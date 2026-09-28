import Link from 'next/link'
import { notFound } from 'next/navigation'

import { ProgressBar, TypeChip } from '@pokegosu/ui/pokemon'

import { dexNo, every, ko, type Named, pokedex, typeNames } from '@/lib/pokedex'

import { FormMarks, FormSprite } from './marks'
import { ShinyChoice } from './shiny'
import { LookLink, Shown } from './shown'
import { Sprite } from './sprite'

type Method = {
  trigger: Named & { id: string }
  level: number | null
  item: Named | null
  held_item: Named | null
  min_happiness: number | null
  time_of_day: string | null
  relative_physical_stats: number | null
  min_beauty: number | null
  chance: number | null
  gender: string | null
  known_move: Named | null
  location: Named | null
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
function takes(method: Method): string {
  const parts: string[] = []
  if (method.item) parts.push(`${ko(method.item)} 사용`)
  else if (method.held_item) parts.push(`${ko(method.held_item)} 지닌 채 ${ko(method.trigger)}`)
  else if (method.trigger.id === 'level-up' && method.level) parts.push(`Lv.${method.level}`)
  else if (method.known_move) parts.push(`${ko(method.known_move)} 배운 채 ${ko(method.trigger)}`)
  else if (method.location) parts.push(`${ko(method.location)}에서 ${ko(method.trigger)}`)
  else if (method.party) parts.push(`${ko(method.trigger)} · 동료 ${ko(method.party)}`)
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
  return parts.join(' · ') || ko(method.trigger)
}

function genderRatio(rate: number): string {
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

/** A form's own name, or 기본 for a default form the games name nothing. */
function formName(form: { ko_form_name: string | null; en_form_name: string | null }): string {
  return form.ko_form_name ?? form.en_form_name ?? '기본'
}

/** Every number the pokedex lists, each built as a file. */
export async function generateStaticParams({ params }: { params: { dex: string } }) {
  const rows = await every((from, to) =>
    pokedex()
      .from('pokedex_entries')
      .select('number')
      .eq('dex', params.dex)
      .eq('is_default', true)
      .order('number')
      .range(from, to),
  )
  return rows.map(({ number }) => ({ number: String(number) }))
}

export default async function Entry({ params }: PageProps<'/[dex]/[number]'>) {
  const { dex, number } = await params
  const n = Number(number)
  if (!Number.isInteger(n) || n < 1) notFound()

  const db = pokedex()
  const [forms, chain, around, kind, types] = await Promise.all([
    // With this pokedex's text on each: each pokedex writes its own.
    db
      .from('pokedex_entries')
      .select('is_default, ko_description, en_description, species:pokedex_species(*)')
      .eq('dex', dex)
      .eq('number', n)
      .order('is_default', { ascending: false })
      .order('species_id'),
    // Every form in this pokedex, only as much as finds a family: follow
    // evolves_from_id, and link each by its number here. A stage this pokedex
    // does not list is left out: Kanto's has no Pichu.
    every((from, to) =>
      db
        .from('pokedex_entries')
        .select('number, is_default, species:pokedex_species(id, evolves_from_id)')
        .eq('dex', dex)
        .order('species_id')
        .range(from, to),
    ),
    // The numbers either side, in the same pokedex.
    db
      .from('pokedex_entries')
      .select('number, species:pokedex_species(ko_name, en_name)')
      .eq('dex', dex)
      .eq('is_default', true)
      .in('number', [n - 1, n + 1])
      .order('number'),
    db.from('pokedex_kinds').select('ko_name, en_name').eq('id', dex).maybeSingle(),
    typeNames(),
  ])
  for (const result of [forms, around, kind]) {
    if (result.error) throw result.error
  }
  if (!kind.data) notFound()
  const dexName = ko(kind.data)
  if (!forms.data?.length) notFound()

  const entries = new Map(
    chain.map(({ number, is_default, species: s }) => [s.id, { number, is_default }]),
  )
  const parents = new Map(chain.map(({ species: s }) => [s.id, s.evolves_from_id]))
  const firstOf = (id: number): number => {
    const parent = parents.get(id)
    return parent ? firstOf(parent) : id
  }
  const stageOf = (id: number): number => {
    const parent = parents.get(id)
    return parent ? stageOf(parent) + 1 : 0
  }
  const firsts = new Set(forms.data.map(({ species: p }) => firstOf(p.id)))
  const familyIds = [...parents.keys()].filter((id) => firsts.has(firstOf(id)))

  // Only the families' own names, rather than every item, move and place.
  const members = await db
    .from('pokedex_species')
    .select(
      `id, slug, ko_name, en_name, front:sprites->>front, front_shiny:sprites->>front_shiny,
      method:pokedex_evolution_methods!evolution_method(
        level, min_happiness, time_of_day, relative_physical_stats, min_beauty, chance, gender,
        trigger:pokedex_evolution_triggers(id, ko_name, en_name),
        item:pokedex_items!item(ko_name, en_name),
        held_item:pokedex_items!held_item(ko_name, en_name),
        known_move:pokedex_moves(ko_name, en_name),
        location:pokedex_locations(ko_name, en_name),
        party:pokedex_species!party_species_id(ko_name, en_name)
      )`,
    )
    .in('id', familyIds)
  if (members.error) throw members.error
  // By stage before number: a baby came in a later generation, so Pichu's
  // number is higher than Raichu's, yet it comes first.
  const everyMember = members.data
    .map((f) => ({ ...f, ...entries.get(f.id)! }))
    .sort((a, b) => stageOf(a.id) - stageOf(b.id) || a.number - b.number)
  const familyOf = (id: number) => everyMember.filter((f) => firstOf(f.id) === firstOf(id))

  // A form's page links by its number, by its name unless it is the default,
  // and with ?gender=female for a female that looks different.
  const hrefOf = (number: number, f: { is_default: boolean; slug: string }, female = false) => {
    const query = new URLSearchParams()
    if (!f.is_default) query.set('form', f.slug)
    if (female) query.set('gender', 'female')
    return query.size ? `/${dex}/${number}?${query}` : `/${dex}/${number}`
  }

  // Every form, and where a female looks different, as Pikachu's tail does,
  // the male and the female each. Each links to itself.
  const manyForms = forms.data.length > 1
  const looks = forms.data.flatMap(({ is_default, species: f }) => {
    const s = f.sprites as {
      front?: string
      front_female?: string
      front_shiny?: string
      front_shiny_female?: string
    }
    const look = (key: string, src: string | undefined, label: string, isFemale: boolean) => ({
      key,
      src,
      shiny: isFemale ? s.front_shiny_female : s.front_shiny,
      label,
      href: hrefOf(n, { is_default, slug: f.slug }, isFemale),
      id: f.id,
      female: isFemale,
    })
    const name = manyForms ? `${formName(f)} ` : ''
    return s.front_female
      ? [
          look(`${f.id}-male`, s.front, `${name}수컷의 모습`, false),
          look(`${f.id}-female`, s.front_female, `${name}암컷의 모습`, true),
        ]
      : [look(`${f.id}`, s.front, formName(f), false)]
  })
  const previous = around.data!.find((e) => e.number === n - 1)
  const next = around.data!.find((e) => e.number === n + 1)
  const slugs = forms.data.map(({ species: f }) => f.slug)

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

      {/* A file cannot tell ?form= from ?gender=, so every look is drawn here
          and the browser shows the one the address asks for. */}
      <ShinyChoice forms={forms.data.map(({ species: f }) => [f.slug, f.id])}>
        {forms.data.flatMap(({ ko_description, en_description, species: p }) => {
          const sprites = p.sprites as {
            artwork?: string
            artwork_shiny?: string
            artwork_female?: string
            artwork_shiny_female?: string
          }
          const description = ko_description ?? en_description
          const family = familyOf(p.id)
          const statTotal = STATS.reduce((sum, [key]) => sum + p[key], 0)
          // Only where she looks different; elsewhere ?gender=female changes nothing.
          const genders = sprites.artwork_female ? [false, true] : [null]
          return genders.map((female) => (
            <Shown key={`${p.id}-${female}`} forms={slugs} form={p.slug} female={female}>
              <header className="flex items-center gap-8">
                <Sprite
                  name={ko(p)}
                  normal={female ? sprites.artwork_female : sprites.artwork}
                  shiny={female ? sprites.artwork_shiny_female : sprites.artwork_shiny}
                />
                <div className="flex flex-col gap-2">
                  <p className="text-muted font-mono text-xs tabular-nums">
                    {dexName} {dexNo(n)}
                  </p>
                  <h1 className="flex items-center gap-2 text-3xl font-semibold tracking-tight">
                    {ko(p)}
                    {manyForms && (
                      <span className="text-muted text-base font-normal tracking-normal">
                        {formName(p)}
                      </span>
                    )}
                    <FormMarks id={p.id} size="lg" />
                  </h1>
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
                  {description && <p className="mt-2 max-w-xl leading-relaxed">{description}</p>}
                </div>
              </header>

              {looks.length > 1 && (
                <section className="space-y-3">
                  <h2 className="text-muted text-sm font-medium">모습</h2>
                  <ul className="flex flex-wrap gap-2">
                    {looks.map((look) => (
                      <li key={look.key}>
                        <LookLink
                          href={look.href}
                          aria-current={
                            look.id === p.id && look.female === !!female ? 'page' : undefined
                          }
                          className="border-line hover:border-line-strong aria-[current=page]:border-accent relative flex w-26 flex-col items-center gap-1 rounded-lg border px-1 py-2 text-center text-[13px]"
                        >
                          <span className="absolute top-1 right-1">
                            <FormMarks id={look.id} />
                          </span>
                          <span className="grid size-24 place-items-center rounded-md">
                            <FormSprite src={look.src} shiny={look.shiny} />
                          </span>
                          {look.label}
                        </LookLink>
                      </li>
                    ))}
                  </ul>
                </section>
              )}

              <section className="grid gap-10 sm:grid-cols-2">
                <div className="space-y-3">
                  <h2 className="text-muted text-sm font-medium">정보</h2>
                  <dl className="grid grid-cols-[4.5rem_minmax(0,1fr)] gap-y-2 text-sm">
                    <dt className="text-muted">키</dt>
                    <dd className="font-mono text-[13px]">{(p.height / 10).toFixed(1)} m</dd>
                    <dt className="text-muted">몸무게</dt>
                    <dd className="font-mono text-[13px]">{(p.weight / 10).toFixed(1)} kg</dd>
                    <dt className="text-muted">성비</dt>
                    <dd className="font-mono text-[13px]">{genderRatio(p.gender_rate)}</dd>
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
                    {family.map((f, i) => (
                      <li key={f.id} className="flex items-center gap-3">
                        {/* The first stage shown has nothing before it here, even
                          where it evolves from one this pokedex leaves out. */}
                        {i > 0 && f.method && (
                          <span className="text-muted text-xs">→ {takes(f.method)}</span>
                        )}
                        <Link
                          href={hrefOf(f.number, f)}
                          aria-current={f.id === p.id ? 'page' : undefined}
                          className="border-line hover:border-line-strong aria-[current=page]:border-accent relative flex flex-col items-center gap-1 rounded-lg border px-3 py-2 text-[13px]"
                        >
                          <span className="absolute top-1 right-1">
                            <FormMarks id={f.id} />
                          </span>
                          <span className="grid size-24 place-items-center rounded-md">
                            <FormSprite
                              src={f.front ?? undefined}
                              shiny={f.front_shiny ?? undefined}
                            />
                          </span>
                          {ko(f)}
                          <span className="text-muted font-mono text-[11px]">
                            {dexNo(f.number)}
                          </span>
                        </Link>
                      </li>
                    ))}
                  </ol>
                </section>
              )}
            </Shown>
          ))
        })}
      </ShinyChoice>
    </main>
  )
}
