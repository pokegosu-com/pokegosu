'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'
import { Artwork } from '@pokegosu/ui/artwork'
import { ProgressBar, TypeChip } from '@pokegosu/ui/pokemon'

import { env } from '@/env'
import { exactTokens } from '@/lib/format'
import {
  eggHint,
  eggSpriteUrl,
  ko,
  levelAt,
  spriteUrl,
  usableItems,
  type Curve,
  type Egg,
  type Named,
  type Pokemon,
} from '@/lib/game'

import { useCountUp } from '../../game/count-up'
import { UseItemLabel } from '../../game/item-label'
import { Gender } from '../../game/gender'
import { Marks } from '../../game/marks'
import { say } from '../../game/say'
import { useGame } from '../../game/use-game'

type Game = ReturnType<typeof useGame>

/** What companion_history() answers with, when the companion is the caller's. */
type History = {
  egg_kind: { id: string } & Named
  created_at: string
  hatched_at: string | null
  main_periods: { started_at: string; ended_at: string | null }[]
}

const MS_PER_LEVEL = 350

const primary =
  'bg-accent text-surface rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50'
const quiet =
  'border-line-strong hover:border-ink rounded-md border px-4 py-2 text-sm font-medium disabled:opacity-50'

function day(at: string): string {
  return new Date(at).toLocaleDateString('ko-KR', { month: '2-digit', day: '2-digit' })
}

/** "09. 24. – 09. 26. · 2일", or from a day up to now for the one still going. */
function period({ started_at, ended_at }: History['main_periods'][number]): string {
  const days = Math.max(
    1,
    Math.round(
      ((ended_at ? new Date(ended_at) : new Date()).getTime() - new Date(started_at).getTime()) /
        86_400_000,
    ),
  )
  return ended_at
    ? `${day(started_at)} – ${day(ended_at)} · ${days}일`
    : `${day(started_at)} 부터 지금까지 · ${days}일`
}

function Records({
  history,
  tokens,
  ribbons,
}: {
  history: History | null
  tokens: number
  ribbons: Pokemon['ribbons']
}) {
  return (
    <section className="grid gap-8 sm:grid-cols-2">
      <div className="space-y-3">
        <h2 className="text-muted text-sm font-medium">기록</h2>
        {history ? (
          <dl className="grid grid-cols-[7rem_minmax(0,1fr)] gap-y-2 text-sm">
            <dt className="text-muted">받은 날</dt>
            <dd className="font-mono text-[13px]">
              {new Date(history.created_at).toLocaleDateString('ko-KR')}
            </dd>
            <dt className="text-muted">받은 알</dt>
            <dd>{ko(history.egg_kind)}</dd>
            {history.hatched_at && (
              <>
                <dt className="text-muted">부화한 날</dt>
                <dd className="font-mono text-[13px]">
                  {new Date(history.hatched_at).toLocaleDateString('ko-KR')}
                </dd>
              </>
            )}
            <dt className="text-muted">받은 토큰</dt>
            <dd className="font-mono text-[13px]">{exactTokens(tokens)}</dd>
            <dt className="text-muted">파트너였던 때</dt>
            <dd className="space-y-0.5 font-mono text-[13px]">
              {history.main_periods.length === 0 ? (
                <span className="text-muted font-sans">아직 없음</span>
              ) : (
                history.main_periods.map((p) => <p key={p.started_at}>{period(p)}</p>)
              )}
            </dd>
          </dl>
        ) : (
          <p className="text-muted text-sm">불러오는 중…</p>
        )}
      </div>
      <div className="space-y-3">
        <h2 className="text-muted text-sm font-medium">리본</h2>
        {ribbons.length > 0 ? (
          <p className="flex flex-wrap gap-1.5">
            {ribbons.map((r) => (
              <span key={r.id} className="bg-ribbon-surface rounded px-1.5 py-0.5 text-xs">
                🎀 {ko(r)}
              </span>
            ))}
          </p>
        ) : (
          <p className="text-muted text-sm">아직 없음</p>
        )}
      </div>
    </section>
  )
}

function PokemonDetail({
  p,
  curve,
  game,
  history,
}: {
  p: Pokemon
  curve: Curve
  game: Game
  history: History | null
}) {
  const { act, busy, box } = game
  const stones = usableItems(p, box?.started ? box.bag : [])
  const { shown, climbing } = useCountUp(p.tokens, (from, to) => {
    const a = levelAt(curve, p.growth_rate, from)?.level ?? 1
    const b = levelAt(curve, p.growth_rate, to)?.level ?? 1
    return Math.min(8000, Math.max(600, (b - a + 1) * MS_PER_LEVEL))
  })
  const at = levelAt(curve, p.growth_rate, shown) ?? {
    level: p.level,
    from: p.level_tokens,
    to: p.next_level_tokens,
  }
  const toNext = at.to === null ? null : Math.ceil(at.to - shown)
  const sprite = spriteUrl(p, 'large')

  return (
    <>
      <header className="flex items-center gap-8">
        <Artwork src={sprite} alt={ko(p)} shiny={p.is_shiny} />
        <div className="flex min-w-0 flex-1 flex-col gap-3">
          {p.is_main && <p className="text-accent text-xs font-medium">파트너</p>}
          <p className="flex items-baseline gap-2">
            {p.is_shiny && <span title="색이 다른 포켓몬">✨</span>}
            <span className="text-3xl font-semibold tracking-tight">{ko(p)}</span>
            <Gender gender={p.gender} />
            <span className="text-muted font-mono text-xs">
              No.{String(p.dex_no).padStart(3, '0')}
            </span>
          </p>
          <p className="flex gap-1">
            {p.types.map((t) => (
              <TypeChip key={t.id} id={t.id} name={ko(t)} />
            ))}
          </p>
          <Marks
            markings={p.markings}
            disabled={busy}
            onChange={(markings) => act({ fn: 'set_markings', companion_id: p.id, markings })}
          />
          {/* Hidden while the level is still counting up, so nothing is
              pressed on a level the bar hasn't reached. */}
          {!climbing && (
            <div className="flex flex-wrap gap-2">
              {p.can_evolve && p.evolves_to && (
                <button
                  type="button"
                  className={primary}
                  disabled={busy}
                  onClick={() => act({ fn: 'evolve', companion_id: p.id })}
                >
                  {ko(p.evolves_to)}(으)로 진화
                </button>
              )}
              {stones.map((e) => (
                <button
                  key={e.item.id}
                  type="button"
                  className={primary}
                  disabled={busy}
                  onClick={() => act({ fn: 'use_item', companion_id: p.id, item_id: e.item.id })}
                >
                  <UseItemLabel item={e.item} />
                </button>
              ))}
              {p.can_receive_egg && (
                <button
                  type="button"
                  className={primary}
                  disabled={busy}
                  onClick={() => act({ fn: 'receive_egg', companion_id: p.id })}
                >
                  알 받기
                </button>
              )}
              {p.ribbons_waiting.map((r) => (
                <button
                  key={r.id}
                  type="button"
                  className={primary}
                  disabled={busy}
                  onClick={() => act({ fn: 'receive_ribbon', companion_id: p.id, ribbon_id: r.id })}
                >
                  {ko(r)} 받기
                </button>
              ))}
              {!p.is_main && (
                <button
                  type="button"
                  className={quiet}
                  disabled={busy}
                  onClick={() => act({ fn: 'set_main', companion_id: p.id })}
                >
                  파트너로
                </button>
              )}
            </div>
          )}
        </div>
      </header>

      <section className="space-y-2">
        <p className="flex items-baseline justify-between font-mono text-xs tabular-nums">
          <span className="text-base font-medium">Lv.{at.level}</span>
          <span className="text-muted">
            {toNext === null ? '최고 레벨' : `다음 레벨까지 ${exactTokens(toNext)} 토큰`}
          </span>
        </p>
        <ProgressBar
          value={shown - at.from}
          max={(at.to ?? shown) - at.from}
          label="다음 레벨까지"
          size="lg"
        />
        {p.workplace_id && (
          <p className="text-muted text-xs">
            의뢰를 하는 중이다.{' '}
            <Link href="/requests" className="text-accent hover:text-ink">
              의뢰
            </Link>
          </p>
        )}
      </section>

      <Records history={history} tokens={p.tokens} ribbons={p.ribbons} />

      <a href={pokedexHref(p)} className="text-accent hover:text-ink text-sm">
        도감에서 보기 →
      </a>
    </>
  )
}

/** This Pokémon's own look in the Pokédex: its form, a female's look, and shiny or not. */
function pokedexHref(p: Pokemon): string {
  const query = new URLSearchParams()
  if (p.form_slug) query.set('form', p.form_slug)
  if (p.gender === 'female') query.set('gender', 'female')
  query.set('shiny', p.is_shiny ? '1' : '0')
  return `${env.NEXT_PUBLIC_POKEDEX_URL}/national/${p.dex_no}?${query}`
}

function EggDetail({ egg, game, history }: { egg: Egg; game: Game; history: History | null }) {
  const { act, busy } = game
  const { shown, climbing } = useCountUp(egg.tokens, () => 1500)
  const ready = !climbing && egg.tokens >= egg.tokens_needed
  return (
    <>
      <header className="flex items-center gap-8">
        <span className="grid size-48 flex-none place-items-center rounded-lg">
          {/* eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web */}
          <img src={eggSpriteUrl} alt="알" className="size-24 [image-rendering:pixelated]" />
        </span>
        <div className="flex min-w-0 flex-1 flex-col gap-3">
          {egg.is_main && <p className="text-accent text-xs font-medium">파트너</p>}
          <p className="text-3xl font-semibold tracking-tight">알</p>
          <p className="text-muted text-sm">{eggHint(egg)}</p>
          <Marks
            markings={egg.markings}
            disabled={busy}
            onChange={(markings) => act({ fn: 'set_markings', companion_id: egg.id, markings })}
          />
          <div className="flex flex-wrap gap-2">
            {ready && (
              <button
                type="button"
                className={primary}
                disabled={busy}
                onClick={() => act({ fn: 'hatch', companion_id: egg.id })}
              >
                부화시키기
              </button>
            )}
            {!egg.is_main && (
              <button
                type="button"
                className={quiet}
                disabled={busy}
                onClick={() => act({ fn: 'set_main', companion_id: egg.id })}
              >
                파트너로
              </button>
            )}
          </div>
        </div>
      </header>

      <section className="space-y-2">
        <p className="text-muted text-right font-mono text-xs tabular-nums">
          {exactTokens(Math.floor(shown))} / {exactTokens(egg.tokens_needed)} 토큰
        </p>
        <ProgressBar value={shown} max={egg.tokens_needed} label="부화까지" size="lg" />
      </section>

      <Records history={history} tokens={egg.tokens} ribbons={[]} />
    </>
  )
}

/** One companion on its own page: the large sprite, what waits for it, and its history. */
export function Detail({ id }: { id: string }) {
  const game = useGame()
  const { box, curve, last, failure } = game
  const [history, setHistory] = useState<History | null>(null)
  const [missing, setMissing] = useState(false)

  // Reloaded after each button: becoming the partner opens a period.
  const version = last
  useEffect(() => {
    let cancelled = false
    createClient()
      .rpc('companion_history', { companion_id: id })
      .then(({ data }) => {
        if (cancelled || !data) return
        const answer = data as { outcome: string } & History
        if (answer.outcome === 'found') setHistory(answer)
        else setMissing(true)
      })
    return () => {
      cancelled = true
    }
  }, [id, version])

  const pokemon = box?.started ? box.pokemon.find((p) => p.id === id) : undefined
  const egg = box?.started ? box.eggs.find((e) => e.id === id) : undefined
  const message = last ? say(box, last.action.fn, last.outcome) : null

  return (
    <>
      <nav className="text-sm">
        <Link href="/box" className="text-muted hover:text-ink">
          ← 박스
        </Link>
      </nav>
      {failure && (
        <p className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">{failure}</p>
      )}
      {message && <p className="bg-accent/10 rounded-md px-3 py-2 text-sm">{message}</p>}
      {pokemon ? (
        <PokemonDetail p={pokemon} curve={curve} game={game} history={history} />
      ) : egg ? (
        <EggDetail egg={egg} game={game} history={history} />
      ) : box && (missing || box.started) ? (
        <p className="text-muted text-sm">박스에 없는 포켓몬입니다.</p>
      ) : (
        <p className="text-muted text-sm">불러오는 중…</p>
      )}
    </>
  )
}
