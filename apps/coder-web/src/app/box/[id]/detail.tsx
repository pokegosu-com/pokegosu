'use client'

import Link from 'next/link'
import { useEffect, useRef, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'
import { Artwork } from '@pokegosu/ui/artwork'
import { ProgressBar, TypeChip } from '@pokegosu/ui/pokemon'

import { env } from '@/env'
import { exactTokens } from '@/lib/format'
import {
  eggHint,
  eggSpriteUrl,
  evolveLabel,
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
import { useLevelFill } from '../../game/level-fill'
import { UseItemLabel } from '../../game/item-label'
import { ActionToasts } from '../../game/action-toasts'
import { cameFrom } from '../../game/came-from'
import { Gender } from '../../game/gender'
import { TokensLeft } from '../../game/tokens-left'
import { Marks } from '../../game/marks'
import { useGame } from '../../game/use-game'

type Game = ReturnType<typeof useGame>

/** What companion_history() answers with, when the companion is the caller's. */
type History = {
  egg_kind: { id: string } & Named
  created_at: string
  hatched_at: string | null
  main_periods: { started_at: string; ended_at: string | null }[]
}

// The clear border makes a primary button as tall as a quiet one, so a row of
// either holds the same height.
// On a phone the game's next step spans the page, under the thumb.
const primary =
  'bg-accent text-surface w-full rounded-md border border-transparent px-4 py-2 text-sm font-medium disabled:opacity-50 sm:w-auto'
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
  const {
    shown,
    at: reached,
    climbing,
  } = useLevelFill(p.tokens, (tokens) => levelAt(curve, p.growth_rate, tokens))
  const at = reached ?? {
    level: p.level,
    from: p.level_tokens,
    to: p.next_level_tokens,
  }
  const sprite = spriteUrl(p, 'large')
  // One out on a request is left alone until it is back: the server refuses
  // every button here for it.
  const working = p.workplace_id !== null
  const { upsideDown, holdToFlip } = useUpsideDown(p.evolves_to?.upside_down ?? false)
  const { spun, tapToSpin } = useSpin(p.evolves_to?.spin ?? false)
  // Inkay evolves with the console turned over, which here is its own
  // render: the button is there only while it is upside down. Milcery
  // evolves on a spin, its render's too: the button is there once it has
  // spun.
  const evolveNow =
    p.evolves_to &&
    (p.can_evolve ||
      (upsideDown && p.evolves_to.upside_down && at.level >= (p.evolves_to.level ?? 0)) ||
      (spun && p.evolves_to.spin))

  return (
    <>
      {/* The partner's own bar is climbing here, so its level waits for it. */}
      {p.is_main && <ActionToasts game={game} level={at.level} />}
      <header className="flex flex-col items-center gap-4 sm:flex-row sm:gap-8">
        <span
          {...holdToFlip}
          {...tapToSpin}
          className={`motion-safe:transition-transform motion-safe:duration-500 ${upsideDown ? 'rotate-180' : ''} ${spun ? 'rotate-360' : ''}`}
        >
          <Artwork src={sprite} alt={ko(p)} shiny={p.is_shiny} from={cameFrom(game.last, p.id)} />
        </span>
        <div className="flex min-w-0 flex-1 flex-col gap-3 self-stretch">
          {p.is_main && <p className="text-accent text-xs font-medium">파트너</p>}
          <p className="flex items-baseline gap-2">
            {p.is_shiny && <span title="색이 다른 포켓몬">✨</span>}
            <span className="text-2xl font-semibold tracking-tight sm:text-3xl">{ko(p)}</span>
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
          {/* The marks hold the row at a button's height with or without
              buttons beside them, so the page does not move as they come
              and go. */}
          <div className="flex min-h-9.5 flex-wrap items-center gap-2">
            <span className="w-full sm:mr-4 sm:w-auto">
              <Marks
                markings={p.markings}
                disabled={busy || working}
                onChange={(markings) => act({ fn: 'set_markings', companion_id: p.id, markings })}
              />
            </span>
            {/* Hidden while the level is still counting up, so nothing is
                pressed on a level the bar hasn't reached. */}
            {working ? (
              <Link href="/requests" className="text-muted hover:text-ink text-xs">
                의뢰를 하는 중
              </Link>
            ) : (
              !climbing && (
                <>
                  {evolveNow && p.evolves_to && (
                    <button
                      type="button"
                      className={primary}
                      disabled={busy}
                      onClick={() => act({ fn: 'evolve', companion_id: p.id })}
                    >
                      {evolveLabel(p.evolves_to)}
                    </button>
                  )}
                  {stones.map((e) => (
                    <button
                      key={e.item.id}
                      type="button"
                      className={primary}
                      disabled={busy}
                      onClick={() =>
                        act({ fn: 'use_item', companion_id: p.id, item_id: e.item.id })
                      }
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
                      onClick={() =>
                        act({ fn: 'receive_ribbon', companion_id: p.id, ribbon_id: r.id })
                      }
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
                </>
              )
            )}
          </div>
        </div>
      </header>

      <section className="space-y-2">
        <p className="flex items-baseline justify-between font-mono text-xs tabular-nums">
          <span className="text-base font-medium">Lv.{at.level}</span>
          <TokensLeft
            curve={curve}
            growthRate={p.growth_rate}
            level={at.level}
            to={at.to}
            tokens={shown}
          />
        </p>
        <ProgressBar
          value={shown - at.from}
          max={(at.to ?? shown) - at.from}
          label="다음 레벨까지"
          animated
          size="lg"
        />
      </section>

      <Records history={history} tokens={p.tokens} ribbons={p.ribbons} />

      <a href={pokedexHref(p)} className="text-accent hover:text-ink text-sm">
        도감에서 보기 →
      </a>
    </>
  )
}

/** How long the render must be held to turn over, and how long it stays so. */
const HOLD_MS = 600
const UPSIDE_DOWN_MS = 5000

/**
 * Holding a Pokémon that evolves upside down turns its render over for a
 * while. Nothing says so: it is the games' console turned over, found by
 * trying. Any other Pokémon only hops when pressed.
 */
function useUpsideDown(flippable: boolean) {
  const [upsideDown, setUpsideDown] = useState(false)
  const hold = useRef<ReturnType<typeof setTimeout> | null>(null)
  const back = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(
    () => () => {
      if (hold.current) clearTimeout(hold.current)
      if (back.current) clearTimeout(back.current)
    },
    [],
  )
  const release = () => {
    if (hold.current) clearTimeout(hold.current)
    hold.current = null
  }
  const holdToFlip = flippable
    ? {
        onPointerDown: () => {
          release()
          hold.current = setTimeout(() => {
            setUpsideDown(true)
            if (back.current) clearTimeout(back.current)
            back.current = setTimeout(() => setUpsideDown(false), UPSIDE_DOWN_MS)
          }, HOLD_MS)
        },
        onPointerUp: release,
        onPointerLeave: release,
        onPointerCancel: release,
        // A long press on a phone would otherwise open the image's menu.
        onContextMenu: (e: { preventDefault: () => void }) => e.preventDefault(),
      }
    : {}
  return { upsideDown: flippable && upsideDown, holdToFlip }
}

/** How many taps, and within how long, spin a Pokémon round. */
const SPIN_TAPS = 5
const SPIN_WITHIN_MS = 1000

/**
 * Tapping a Pokémon that evolves on a spin, as Milcery does, five times in a
 * second spins its render round once, and from then on it may evolve. As
 * with Inkay, nothing says so.
 */
function useSpin(spinnable: boolean) {
  const [spun, setSpun] = useState(false)
  const taps = useRef<number[]>([])
  const tapToSpin =
    spinnable && !spun
      ? {
          onPointerDown: () => {
            const now = Date.now()
            taps.current = [...taps.current.filter((t) => now - t < SPIN_WITHIN_MS), now]
            if (taps.current.length >= SPIN_TAPS) setSpun(true)
          },
        }
      : {}
  return { spun: spinnable && spun, tapToSpin }
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
      <header className="flex flex-col items-center gap-4 sm:flex-row sm:gap-8">
        <span className="grid size-48 flex-none place-items-center rounded-lg">
          {/* eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web */}
          <img src={eggSpriteUrl} alt="알" className="size-24 [image-rendering:pixelated]" />
        </span>
        <div className="flex min-w-0 flex-1 flex-col gap-3 self-stretch">
          {egg.is_main && <p className="text-accent text-xs font-medium">파트너</p>}
          <p className="text-2xl font-semibold tracking-tight sm:text-3xl">알</p>
          <p className="text-muted text-sm">{eggHint(egg)}</p>
          <div className="flex min-h-9.5 flex-wrap items-center gap-2">
            <span className="w-full sm:mr-4 sm:w-auto">
              <Marks
                markings={egg.markings}
                disabled={busy}
                onChange={(markings) => act({ fn: 'set_markings', companion_id: egg.id, markings })}
              />
            </span>
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
        <ProgressBar value={shown} max={egg.tokens_needed} label="부화까지" size="lg" animated />
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
      {!pokemon?.is_main && <ActionToasts game={game} />}
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
