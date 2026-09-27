'use client'

import { useEffect, useState } from 'react'

import { PokemonTile } from '@pokegosu/ui/pokemon'

import { exactTokens } from '@/lib/format'
import { MARKS, eggSpriteUrl, ko, markOf, spriteUrl, type Egg, type Pokemon } from '@/lib/game'

import { useGame } from '../game/use-game'

type Kind = 'all' | 'pokemon' | 'eggs'
type Sort = 'recent' | 'level' | 'dex' | 'name'
/** Per mark: not filtered, on in either colour, blue, or red. */
type MarkFilter = null | 'any' | 1 | 2

type View = {
  kind: Kind
  query: string
  sort: Sort
  type: string
  shiny: boolean
  task: boolean
  marks: MarkFilter[]
}

const initial: View = {
  kind: 'all',
  query: '',
  sort: 'recent',
  type: '',
  shiny: false,
  task: false,
  marks: MARKS.map(() => null),
}

const STORED = 'coder.box.view.v2'

/**
 * The last sort and filters are kept in this browser, so the box opens the
 * way it was left. The search is not: a name typed once is rarely wanted
 * again.
 */
function useView() {
  const [view, setView] = useState<View>(initial)
  useEffect(() => {
    try {
      const saved = localStorage.getItem(STORED)
      // eslint-disable-next-line react-hooks/set-state-in-effect -- localStorage exists only after hydration
      if (saved) setView({ ...initial, ...(JSON.parse(saved) as Partial<View>), query: '' })
    } catch {
      // No storage, or something unreadable in it: start from the defaults.
    }
  }, [])
  const update = (change: Partial<View>) => {
    setView((v) => {
      const next = { ...v, ...change }
      try {
        localStorage.setItem(STORED, JSON.stringify({ ...next, query: '' }))
      } catch {
        // Unsaved is fine; the view still changes.
      }
      return next
    })
  }
  return [view, update] as const
}

/** A Pokémon or an egg, as the box lists them together. */
type Item =
  | {
      kind: 'pokemon'
      id: string
      name: string
      at: string
      level: number
      dex: number
      p: Pokemon
    }
  | { kind: 'egg'; id: string; name: string; at: string; level: 0; dex: number; e: Egg }

const collator = new Intl.Collator('ko')

const sorts: Record<Sort, (a: Item, b: Item) => number> = {
  recent: (a, b) => b.at.localeCompare(a.at),
  level: (a, b) => b.level - a.level || b.at.localeCompare(a.at),
  dex: (a, b) => a.dex - b.dex || b.at.localeCompare(a.at),
  name: (a, b) => collator.compare(a.name, b.name) || b.at.localeCompare(a.at),
}

/** An action the game is waiting for: evolve, hatch, an egg, a ribbon. */
function hasTask(item: Item): boolean {
  if (item.kind === 'egg') return item.e.tokens >= item.e.tokens_needed
  const p = item.p
  return p.can_evolve || p.can_receive_egg || p.ribbons_waiting.length > 0
}

function matches(item: Item, view: View): boolean {
  if (view.kind === 'pokemon' && item.kind !== 'pokemon') return false
  if (view.kind === 'eggs' && item.kind !== 'egg') return false
  const query = view.query.trim()
  if (query && !item.name.includes(query)) return false
  if (view.task && !hasTask(item)) return false
  if (view.shiny && !(item.kind === 'pokemon' && item.p.is_shiny)) return false
  if (view.type && !(item.kind === 'pokemon' && item.p.types.some((t) => t.id === view.type)))
    return false
  const markings = item.kind === 'pokemon' ? item.p.markings : item.e.markings
  return view.marks.every((want, i) => {
    const has = markOf(markings, i)
    return want === null || (want === 'any' ? has !== 0 : has === want)
  })
}

const control =
  'border-line-strong bg-surface rounded-md border px-2.5 py-1.5 text-[13px] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent'
const toggle =
  'rounded-md border px-2.5 py-1.5 text-[13px] border-line aria-pressed:border-ink aria-pressed:bg-surface-raised'
const MARK_TITLES = ['마킹 무시', '마킹 있음', '파랑', '빨강']

export function BoxView() {
  const { box, failure } = useGame()
  const [view, update] = useView()

  if (failure) {
    return <p className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">{failure}</p>
  }
  if (!box) return <p className="text-muted text-sm">불러오는 중…</p>
  if (!box.started) {
    return <p className="text-muted text-sm">아직 알을 받지 않았습니다. 대시보드에서 시작하세요.</p>
  }

  const items: Item[] = [
    ...box.pokemon.map((p): Item => ({
      kind: 'pokemon',
      id: p.id,
      name: ko(p),
      at: p.hatched_at,
      level: p.level,
      dex: p.dex_no,
      p,
    })),
    ...box.eggs.map((e): Item => ({
      kind: 'egg',
      id: e.id,
      name: '알',
      at: e.created_at,
      level: 0,
      dex: Number.MAX_SAFE_INTEGER,
      e,
    })),
  ]
  const types = [
    ...new Map(box.pokemon.flatMap((p) => p.types).map((t) => [t.id, ko(t)])).entries(),
  ].sort((a, b) => collator.compare(a[1], b[1]))
  // The partner comes first whatever the sort.
  const shown = items
    .filter((item) => matches(item, view))
    .sort(
      (a, b) =>
        Number(b.id === box.main_companion_id) - Number(a.id === box.main_companion_id) ||
        sorts[view.sort](a, b),
    )
  const filtered =
    view.kind !== 'all' ||
    view.query.trim() !== '' ||
    view.type !== '' ||
    view.shiny ||
    view.task ||
    view.marks.some((m) => m !== null)

  return (
    <>
      <div className="flex items-baseline gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">박스</h1>
        <span className="text-muted font-mono text-xs tabular-nums">
          {filtered
            ? `${shown.length} / ${items.length}`
            : `포켓몬 ${box.pokemon.length} · 알 ${box.eggs.length}`}
        </span>
      </div>

      <div className="border-line flex flex-col gap-3 border-b pb-4">
        <div className="flex flex-wrap items-center gap-3">
          <input
            type="search"
            aria-label="이름으로 찾기"
            placeholder="이름으로 찾기"
            value={view.query}
            onChange={(e) => update({ query: e.target.value })}
            className={`${control} w-56`}
          />
          <div
            role="group"
            aria-label="종류"
            className="bg-surface-raised flex gap-0.5 rounded-lg p-0.5"
          >
            {(
              [
                ['all', '전체'],
                ['pokemon', '포켓몬'],
                ['eggs', '알'],
              ] as const
            ).map(([kind, label]) => (
              <button
                key={kind}
                type="button"
                aria-pressed={view.kind === kind}
                onClick={() => update({ kind })}
                className="text-muted aria-pressed:bg-surface aria-pressed:text-ink aria-pressed:ring-line rounded-md px-3 py-1 text-[13px] font-medium aria-pressed:ring-1"
              >
                {label}
              </button>
            ))}
          </div>
          <label className="text-muted ml-auto flex items-center gap-2 text-[13px]">
            정렬
            <select
              value={view.sort}
              onChange={(e) => update({ sort: e.target.value as Sort })}
              className={control}
            >
              <option value="recent">최근 받은 순</option>
              <option value="level">레벨 높은 순</option>
              <option value="dex">도감 번호 순</option>
              <option value="name">이름 순</option>
            </select>
          </label>
        </div>
        <div className="flex flex-wrap items-center gap-3">
          <button
            type="button"
            aria-pressed={view.task}
            onClick={() => update({ task: !view.task })}
            className={`${toggle} flex items-center gap-1.5`}
          >
            <i className="bg-accent size-1.5 rounded-full" />할 일 있음
          </button>
          <button
            type="button"
            aria-pressed={view.shiny}
            onClick={() => update({ shiny: !view.shiny })}
            className={toggle}
          >
            ✨ 색이 다른
          </button>
          <label className="text-muted flex items-center gap-2 text-[13px]">
            타입
            <select
              value={view.type}
              onChange={(e) => update({ type: e.target.value })}
              className={control}
            >
              <option value="">모두</option>
              {types.map(([id, name]) => (
                <option key={id} value={id}>
                  {name}
                </option>
              ))}
            </select>
          </label>
          <span role="group" aria-label="마킹" className="flex items-center gap-1">
            <span className="text-muted mr-1 text-[13px]">마킹</span>
            {MARKS.map((mark, i) => {
              const want = view.marks[i]
              const states: MarkFilter[] = [null, 'any', 1, 2]
              const state = states.indexOf(want)
              return (
                <button
                  key={mark}
                  type="button"
                  aria-label={`${mark} ${MARK_TITLES[state]}`}
                  title={MARK_TITLES[state]}
                  aria-pressed={want !== null}
                  onClick={() =>
                    update({
                      marks: view.marks.map((m, j) =>
                        j === i ? states[(states.indexOf(m) + 1) % states.length] : m,
                      ),
                    })
                  }
                  className={`${toggle} size-8 px-0 ${want === 1 ? 'text-mark-blue' : want === 2 ? 'text-mark-red' : want === null ? 'text-muted' : ''}`}
                >
                  {mark}
                </button>
              )
            })}
          </span>
          {filtered && (
            <button
              type="button"
              onClick={() => update({ ...initial, sort: view.sort })}
              className="text-accent text-[13px]"
            >
              필터 지우기
            </button>
          )}
        </div>
      </div>

      {shown.length > 0 ? (
        <ol className="grid grid-cols-3 gap-2 sm:grid-cols-6">
          {shown.map((item) => (
            <li key={item.id} className="grid">
              {item.kind === 'pokemon' ? (
                <PokemonTile
                  href={`/box/${item.id}`}
                  name={item.name}
                  caption={`Lv.${item.p.level}`}
                  sprite={spriteUrl(item.p)}
                  partner={item.id === box.main_companion_id}
                  shiny={item.p.is_shiny}
                  task={hasTask(item)}
                />
              ) : (
                <PokemonTile
                  href={`/box/${item.id}`}
                  name="알"
                  caption={`${exactTokens(item.e.tokens)} / ${exactTokens(item.e.tokens_needed)}`}
                  sprite={eggSpriteUrl}
                  partner={item.id === box.main_companion_id}
                  egg
                  task={hasTask(item)}
                />
              )}
            </li>
          ))}
        </ol>
      ) : (
        <div className="flex flex-col items-center gap-2 py-12">
          <p className="font-medium">
            {items.length === 0 ? '박스가 비어 있습니다' : '조건에 맞는 포켓몬이 없습니다'}
          </p>
          {filtered && (
            <button
              type="button"
              onClick={() => update({ ...initial, sort: view.sort })}
              className="text-accent text-[13px]"
            >
              필터 지우기
            </button>
          )}
        </div>
      )}
      <p className="text-muted text-xs">
        파트너는 정렬과 관계없이 맨 앞에 옵니다. 파란 점은 진화, 부화, 알, 리본처럼 기다리는 일이
        있다는 뜻입니다.
      </p>
    </>
  )
}
