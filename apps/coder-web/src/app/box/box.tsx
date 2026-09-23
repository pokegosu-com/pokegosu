'use client'

import { useEffect, useState } from 'react'

import { MARKS, ko, markOf, type Pokemon } from '@/lib/game'

import { EggCard, PokemonCard } from '../game/cards'
import { Panel } from '../game/panel'
import { useGame } from '../game/use-game'

type Sort = 'recent' | 'dex' | 'name'
/** Per mark: not filtered, on in either colour, blue, or red. */
type MarkFilter = null | 'any' | 1 | 2

type View = {
  tab: 'pokemon' | 'eggs'
  sort: Sort
  types: string[]
  shiny: boolean
  evolvable: boolean
  marks: MarkFilter[]
}

const initial: View = {
  tab: 'pokemon',
  sort: 'recent',
  types: [],
  shiny: false,
  evolvable: false,
  marks: MARKS.map(() => null),
}

const STORED = 'coder.box.view'

/** The last sort and filters are kept in this browser, so the box opens the way it was left. */
function useView() {
  const [view, setView] = useState<View>(initial)
  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORED)
      // eslint-disable-next-line react-hooks/set-state-in-effect -- localStorage exists only after hydration
      if (saved) setView({ ...initial, ...(JSON.parse(saved) as Partial<View>) })
    } catch {
      // No storage, or something unreadable in it: start from the defaults.
    }
  }, [])
  const update = (change: Partial<View>) => {
    setView((v) => {
      const next = { ...v, ...change }
      try {
        localStorage.setItem(STORED, JSON.stringify(next))
      } catch {
        // Unsaved is fine; the view still changes.
      }
      return next
    })
  }
  return [view, update] as const
}

const collator = new Intl.Collator('ko')

const sorts: Record<Sort, (a: Pokemon, b: Pokemon) => number> = {
  recent: (a, b) => b.hatched_at.localeCompare(a.hatched_at),
  dex: (a, b) => a.dex_no - b.dex_no || b.hatched_at.localeCompare(a.hatched_at),
  name: (a, b) =>
    collator.compare(ko(a.names), ko(b.names)) || b.hatched_at.localeCompare(a.hatched_at),
}

function matches(p: Pokemon, view: View): boolean {
  if (view.shiny && !p.is_shiny) return false
  if (view.evolvable && !p.can_evolve) return false
  if (!view.types.every((t) => p.types.some((pt) => pt.id === t))) return false
  return view.marks.every((want, i) => {
    const has = markOf(p.markings, i)
    return want === null || (want === 'any' ? has !== 0 : has === want)
  })
}

const chip = 'rounded-full border px-2.5 py-1 text-xs'
const on = 'border-accent bg-accent/10 text-ink'
const off = 'border-muted/30 text-muted hover:border-muted'

export function BoxView() {
  const game = useGame()
  const [view, update] = useView()
  const { box, act, busy } = game

  const pokemon = box?.started ? box.pokemon : []
  const eggs = box?.started ? box.eggs : []
  const types = [
    ...new Map(pokemon.flatMap((p) => p.types).map((t) => [t.id, ko(t.names)])).entries(),
  ].sort((a, b) => collator.compare(a[1], b[1]))
  const shown = pokemon.filter((p) => matches(p, view)).sort(sorts[view.sort])

  return (
    <>
      <Panel game={game} />

      {box?.started && (
        <section className="space-y-4">
          <nav className="border-muted/25 flex gap-4 border-b text-sm">
            {(
              [
                ['pokemon', `포켓몬 박스 ${pokemon.length}`],
                ['eggs', `알 박스 ${eggs.length}`],
              ] as const
            ).map(([tab, label]) => (
              <button
                key={tab}
                type="button"
                onClick={() => update({ tab })}
                className={`-mb-px border-b-2 pb-2 ${view.tab === tab ? 'border-accent' : 'text-muted border-transparent'}`}
              >
                {label}
              </button>
            ))}
          </nav>

          {view.tab === 'eggs' ? (
            <ul className="grid gap-3 sm:grid-cols-2">
              {eggs.map((egg) => (
                <li key={egg.id}>
                  <EggCard egg={egg} act={act} busy={busy} />
                </li>
              ))}
              {eggs.length === 0 && (
                <li className="text-muted text-sm">
                  알이 없습니다. Lv.50 이 되면 알을 받을 수 있습니다.
                </li>
              )}
            </ul>
          ) : (
            <>
              <div className="space-y-2">
                <div className="flex flex-wrap items-center gap-2">
                  <select
                    value={view.sort}
                    onChange={(e) => update({ sort: e.target.value as Sort })}
                    className="border-muted/30 bg-surface rounded-md border px-2 py-1 text-xs"
                  >
                    <option value="recent">최근 획득</option>
                    <option value="dex">도감 번호</option>
                    <option value="name">이름</option>
                  </select>
                  <button
                    type="button"
                    className={`${chip} ${view.shiny ? on : off}`}
                    onClick={() => update({ shiny: !view.shiny })}
                  >
                    ✨ 색이 다른
                  </button>
                  <button
                    type="button"
                    className={`${chip} ${view.evolvable ? on : off}`}
                    onClick={() => update({ evolvable: !view.evolvable })}
                  >
                    진화 가능
                  </button>
                  <span className="flex gap-1">
                    {MARKS.map((mark, i) => {
                      const want = view.marks[i]
                      const next: MarkFilter[] = [null, 'any', 1, 2]
                      return (
                        <button
                          key={mark}
                          type="button"
                          title={['마크 무시', '마크 있음', '파랑', '빨강'][next.indexOf(want)]}
                          onClick={() =>
                            update({
                              marks: view.marks.map((m, j) =>
                                j === i ? next[(next.indexOf(m) + 1) % next.length] : m,
                              ),
                            })
                          }
                          className={`${chip} ${want === null ? off : on} ${want === 1 ? 'text-sky-500' : want === 2 ? 'text-rose-500' : ''}`}
                        >
                          {mark}
                        </button>
                      )
                    })}
                  </span>
                </div>
                <div className="flex flex-wrap gap-2">
                  {types.map(([id, name]) => {
                    const chosen = view.types.includes(id)
                    return (
                      <button
                        key={id}
                        type="button"
                        className={`${chip} ${chosen ? on : off}`}
                        onClick={() =>
                          update({
                            types: chosen
                              ? view.types.filter((t) => t !== id)
                              : [...view.types, id],
                          })
                        }
                      >
                        {name}
                      </button>
                    )
                  })}
                </div>
              </div>

              <ul className="grid gap-3 sm:grid-cols-2">
                {shown.map((p) => (
                  <li key={p.id}>
                    <PokemonCard pokemon={p} act={act} busy={busy} />
                  </li>
                ))}
                {shown.length === 0 && (
                  <li className="text-muted text-sm">
                    {pokemon.length === 0
                      ? '아직 부화한 포켓몬이 없습니다.'
                      : '조건에 맞는 포켓몬이 없습니다.'}
                  </li>
                )}
              </ul>
            </>
          )}
        </section>
      )}
    </>
  )
}
