'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { Artwork } from '@pokegosu/ui/artwork'
import { Command } from '@pokegosu/ui/command'
import { ProgressBar, TypeChip } from '@pokegosu/ui/pokemon'

import { compactTokens, exactTokens } from '@/lib/format'
import {
  eggHint,
  eggSpriteUrl,
  ko,
  levelAt,
  spriteUrl,
  usableItems,
  type Box,
  type Curve,
} from '@/lib/game'
import { HOUR, floorHour, lastDayOf, loadUsage, providerColors, sum, type Usage } from '@/lib/usage'

import { HourChart, Legend } from './charts'
import { useCountUp } from './game/count-up'
import { Gender } from './game/gender'
import { say } from './game/say'
import { useGame, type Opening } from './game/use-game'

type Game = ReturnType<typeof useGame>

const primary =
  'bg-accent text-surface rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50'

/** A level's worth of climbing takes this long, however many tokens it is. */
const MS_PER_LEVEL = 350

function Notice({ children }: { children: React.ReactNode }) {
  return (
    <p role="alert" className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">
      {children}
    </p>
  )
}

/** "+18,240 토큰 · Lv.13 → Lv.15": what opening the page put into the partner. */
function OpeningLine({ opening }: { opening: Opening }) {
  const levels =
    opening.level_before !== null && opening.level_after !== opening.level_before
      ? ` · Lv.${opening.level_before} → Lv.${opening.level_after}`
      : ''
  return (
    <p className="flex items-baseline gap-2 text-sm">
      <span className="text-accent font-mono font-medium tabular-nums">
        +{exactTokens(opening.tokens)} 토큰
      </span>
      <span className="text-muted">지난 방문 이후{levels}</span>
    </p>
  )
}

/**
 * What the game is waiting for from the partner, as buttons, so it is done
 * from here rather than its own page. Once one is pressed, the line under them
 * says what it did, in place of what opening the page did.
 */
function Tasks({
  box,
  game,
  acted,
  children,
}: {
  box: Extract<Box, { started: true }>
  game: Game
  acted: boolean
  children: React.ReactNode
}) {
  const { last, opening } = game
  const message = acted && last ? say(box, last.action.fn, last.outcome) : null
  return (
    <>
      <div className="flex flex-wrap gap-2 empty:hidden">{children}</div>
      {message ? (
        <p className="bg-accent/10 rounded-md px-3 py-2 text-sm">{message}</p>
      ) : (
        !acted &&
        opening?.companion_id === box.main_companion_id && <OpeningLine opening={opening} />
      )}
    </>
  )
}

/**
 * The tokens used but not yet given to any companion: what is left once the
 * partner can take no more, or while an egg waits to hatch. It can be below
 * zero when the game's balance changed after they were given.
 */
function Leftover({ balance }: { balance: string }) {
  return (
    <section
      aria-labelledby="leftover"
      className="border-line flex flex-col justify-center gap-2 rounded-lg border p-6"
    >
      <h2 id="leftover" className="text-muted text-sm font-medium">
        남은 토큰
      </h2>
      <p className="text-2xl font-medium" title={`${exactTokens(balance)} 토큰`}>
        <span className="font-mono tabular-nums">{compactTokens(BigInt(balance))}</span> 토큰
      </p>
    </section>
  )
}

function PokemonPartner({
  box,
  curve,
  game,
  acted,
  onAct,
}: {
  box: Extract<Box, { started: true }>
  curve: Curve
  game: Game
  acted: boolean
  onAct: () => void
}) {
  const p = box.pokemon.find((c) => c.id === box.main_companion_id)!
  // The claim lands all at once; the partner climbs to it a level at a time,
  // along the same curve the server used.
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
    <section
      aria-label="파트너"
      className="border-accent flex items-center gap-8 rounded-lg border p-6"
    >
      <Artwork src={sprite} alt={ko(p)} shiny={p.is_shiny} />
      <div className="flex min-w-0 flex-1 flex-col gap-3.5">
        <div className="space-y-1">
          <p className="text-accent text-xs font-medium">파트너</p>
          <p className="flex items-baseline gap-2">
            {p.is_shiny && <span title="색이 다른 포켓몬">✨</span>}
            <span className="text-3xl font-semibold tracking-tight">{ko(p)}</span>
            <Gender gender={p.gender} />
            <span className="text-muted font-mono text-xs">
              No.{String(p.dex_no).padStart(3, '0')}
            </span>
          </p>
        </div>
        <p className="flex gap-1">
          {p.types.map((t) => (
            <TypeChip key={t.id} id={t.id} name={ko(t)} />
          ))}
        </p>
        <div className="space-y-1.5">
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
        </div>
        {/* Hidden while the level is still counting up, so nothing is
            pressed on a level the bar hasn't reached. */}
        {!climbing && (
          <Tasks box={box} game={game} acted={acted}>
            {p.can_evolve && p.evolves_to && (
              <button
                type="button"
                className={primary}
                disabled={game.busy}
                onClick={() => {
                  onAct()
                  game.act({ fn: 'evolve', companion_id: p.id })
                }}
              >
                {ko(p.evolves_to)}(으)로 진화
              </button>
            )}
            {p.can_receive_egg && (
              <button
                type="button"
                className={primary}
                disabled={game.busy}
                onClick={() => {
                  onAct()
                  game.act({ fn: 'receive_egg', companion_id: p.id })
                }}
              >
                알 받기
              </button>
            )}
            {p.ribbons_waiting.map((r) => (
              <button
                key={r.id}
                type="button"
                className={primary}
                disabled={game.busy}
                onClick={() => {
                  onAct()
                  game.act({ fn: 'receive_ribbon', companion_id: p.id, ribbon_id: r.id })
                }}
              >
                {ko(r)} 받기
              </button>
            ))}
            {usableItems(p, box.bag).map((e) => (
              <button
                key={e.item.id}
                type="button"
                className={primary}
                disabled={game.busy}
                onClick={() => {
                  onAct()
                  game.act({ fn: 'use_item', companion_id: p.id, item_id: e.item.id })
                }}
              >
                {ko(e.item)} 사용
              </button>
            ))}
          </Tasks>
        )}
        <Link href={`/box/${p.id}`} className="text-accent hover:text-ink text-sm">
          자세히 보기 →
        </Link>
      </div>
    </section>
  )
}

function EggPartner({
  box,
  game,
  acted,
  onAct,
}: {
  box: Extract<Box, { started: true }>
  game: Game
  acted: boolean
  onAct: () => void
}) {
  const egg = box.eggs.find((c) => c.id === box.main_companion_id)!
  const { shown, climbing } = useCountUp(egg.tokens, () => 1500)
  return (
    <section
      aria-label="파트너"
      className="border-accent flex items-center gap-8 rounded-lg border p-6"
    >
      <span className="grid size-48 flex-none place-items-center rounded-lg">
        {/* eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web */}
        <img src={eggSpriteUrl} alt="알" className="size-24 [image-rendering:pixelated]" />
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-3.5">
        <div className="space-y-1">
          <p className="text-accent text-xs font-medium">파트너</p>
          <p className="text-3xl font-semibold tracking-tight">알</p>
          <p className="text-muted text-sm">{eggHint(egg)}</p>
        </div>
        <div className="space-y-1.5">
          <p className="text-muted text-right font-mono text-xs tabular-nums">
            {exactTokens(Math.floor(shown))} / {exactTokens(egg.tokens_needed)} 토큰
          </p>
          <ProgressBar value={shown} max={egg.tokens_needed} label="부화까지" size="lg" />
        </div>
        {!climbing && (
          <Tasks box={box} game={game} acted={acted}>
            {egg.tokens >= egg.tokens_needed && (
              <button
                type="button"
                className={primary}
                disabled={game.busy}
                onClick={() => {
                  onAct()
                  game.act({ fn: 'hatch', companion_id: egg.id })
                }}
              >
                부화시키기
              </button>
            )}
          </Tasks>
        )}
        <Link href={`/box/${egg.id}`} className="text-accent hover:text-ink text-sm">
          자세히 보기 →
        </Link>
      </div>
    </section>
  )
}

const STEPS = [
  {
    title: 'PokeGosu CLI 설치',
    command: 'curl -fsSL https://pokegosu.com/install-cli.sh | sh',
    hint: '~/.local/bin 에 설치되고, sudo 는 필요 없습니다.',
  },
  {
    title: '이 기기를 계정에 연결',
    command: 'pokegosu auth login',
    hint: '브라우저가 열리면 터미널의 코드와 같은지 확인하고 등록하세요.',
  },
  {
    title: '기록을 보내는 훅 확인',
    command: 'pokegosu coder hook doctor',
    hint: '이벤트마다 훅이 있는지, 로그 폴더가 있는지 확인하고, 문제가 있으면 고치는 방법을 알려줍니다.',
  },
]

function Empty() {
  return (
    <section className="flex flex-col gap-8">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">아직 기록이 없습니다</h1>
        <p className="text-muted">
          코딩 에이전트를 쓰는 기기를 연결하면, 에이전트가 쓴 토큰이 여기에 쌓이고 포켓몬이
          자랍니다.
        </p>
      </div>
      <ol className="border-line divide-line divide-y rounded-lg border">
        {STEPS.map((s, i) => (
          <li key={s.command} className="grid grid-cols-[2rem_minmax(0,1fr)] gap-3 p-4">
            <span className="text-muted font-mono text-sm leading-6 font-medium">{i + 1}</span>
            <div className="space-y-2">
              <p className="text-sm leading-6 font-medium">{s.title}</p>
              <Command command={s.command} />
              <p className="text-muted text-xs">{s.hint}</p>
            </div>
          </li>
        ))}
      </ol>
    </section>
  )
}

function LastDay({ usage, now }: { usage: Usage; now: Date }) {
  const hours = lastDayOf(usage, now)
  const colors = providerColors(usage.providers)
  const order = usage.providers.map((p) => p.provider)
  const total = hours.reduce((a, h) => a + sum(h), 0)
  return (
    <section className="flex flex-col gap-4">
      <div className="flex items-baseline justify-between">
        <h2 className="text-muted text-sm font-medium">최근 24시간</h2>
        <span className="font-mono text-sm font-medium tabular-nums">
          {exactTokens(total)} 토큰
        </span>
      </div>
      {usage.providers.length > 1 && <Legend providers={usage.providers} colors={colors} />}
      <HourChart hours={hours} colors={colors} order={order} first={(now.getHours() + 1) % 24} />
      <Link href="/usage" className="text-accent hover:text-ink self-end text-sm">
        사용량 전체 보기 →
      </Link>
    </section>
  )
}

/**
 * The partner first, and the last 24 hours of usage beneath it, so the chart
 * is never nearly empty just after midnight. Opening this page claims the
 * tokens earned since the last visit, so the partner is seen climbing.
 */
export function Dashboard() {
  const game = useGame()
  const { box, curve, busy, act } = game
  // Until a button here is pressed, the partner's card says what opening the
  // page gave it; after, what the button did.
  const [acted, setActed] = useState(false)
  const onAct = () => setActed(true)
  const [recent, setRecent] = useState<{ usage: Usage; now: Date } | null>(null)
  const [failure, setFailure] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    async function load() {
      const now = new Date()
      try {
        const usage = await loadUsage(new Date(floorHour(now).getTime() - 23 * HOUR), now)
        if (!cancelled) setRecent({ usage, now })
      } catch (error) {
        if (!cancelled) setFailure((error as Error).message)
      }
    }
    load()
    // A machine syncs every few minutes; a minute is fresh enough to watch.
    const timer = setInterval(load, 60_000)
    return () => {
      cancelled = true
      clearInterval(timer)
    }
  }, [])

  const problem = failure ?? game.failure
  if (!box || !recent) {
    return problem ? <Notice>{problem}</Notice> : <p className="text-muted text-sm">불러오는 중…</p>
  }

  const nothingYet = recent.usage.hours.length === 0 && BigInt(box.balance) === 0n
  if (nothingYet && !box.started) return <Empty />

  return (
    <>
      {problem && <Notice>{problem}</Notice>}
      {!box.started ? (
        <section className="border-line space-y-3 rounded-lg border p-6">
          <p className="text-sm">
            지금까지 쓴 토큰{' '}
            <span className="font-mono tabular-nums">{exactTokens(box.balance)}</span> 이 기다리고
            있습니다. 알을 받아 시작하세요.
          </p>
          <button
            type="button"
            disabled={busy}
            onClick={() => act({ fn: 'start_game' })}
            className="bg-accent text-surface rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            알 받기
          </button>
        </section>
      ) : (
        <div className="grid gap-3 sm:grid-cols-[minmax(0,1fr)_14rem]">
          {box.pokemon.some((p) => p.id === box.main_companion_id) ? (
            <PokemonPartner box={box} curve={curve} game={game} acted={acted} onAct={onAct} />
          ) : (
            <EggPartner box={box} game={game} acted={acted} onAct={onAct} />
          )}
          <Leftover balance={box.balance} />
        </div>
      )}
      {nothingYet ? <Empty /> : <LastDay usage={recent.usage} now={recent.now} />}
    </>
  )
}
