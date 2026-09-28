'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'
import { Command } from '@pokegosu/ui/command'
import { ProgressBar, TypeChip } from '@pokegosu/ui/pokemon'

import { env } from '@/env'
import { points } from '@/lib/format'
import { aptitudeLine, ko, spriteUrl, type Work, type Workplace } from '@/lib/game'

import type { Outcome } from '../game/use-game'
import { useWork, type WorkAction } from '../game/use-work'

type Started = Extract<Work, { started: true }>

const primary =
  'bg-accent text-surface rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50'
const quiet =
  'border-line-strong hover:border-ink rounded-md border px-4 py-2 text-sm font-medium disabled:opacity-50'

/** Hours since the last sync from any machine, or null if none has synced. */
function useHoursSinceSync() {
  const [hours, setHours] = useState<number | null>(null)
  useEffect(() => {
    createClient()
      .from('devices')
      .select('last_sync_at')
      .is('revoked_at', null)
      .not('last_sync_at', 'is', null)
      .order('last_sync_at', { ascending: false })
      .limit(1)
      .then(({ data }) => {
        const at = data?.[0]?.last_sync_at as string | undefined
        if (at) setHours(Math.floor((Date.now() - new Date(at).getTime()) / 3_600_000))
      })
  }, [])
  return hours
}

function say(action: WorkAction, o: Outcome): string | null {
  switch (`${action.fn}:${o.outcome}`) {
    case 'settle:settled':
      return `의뢰를 마쳤다! ${points(Number(o.points))} 를 받았다!`
    case 'settle_trainer:settled':
      return Number(o.bonus) > 0
        ? `${points(Number(o.points))} 와 보너스 ${points(Number(o.bonus))} 를 받았다!`
        : `${points(Number(o.points))} 를 받았다!`
    case 'reroll:rerolled':
      return '새 의뢰가 들어왔다.'
    case 'assign:assigned':
      return '의뢰를 하러 떠났다.'
    default:
      return null
  }
}

/** A pixel sprite at the size the card gives it, standing on the card itself. */
function Sprite({ src, size }: { src: string | undefined; size: 'sm' | 'md' | 'lg' }) {
  const box = { sm: 'size-10', md: 'size-14', lg: 'size-24' }[size]
  return (
    <span className={`grid flex-none place-items-center ${box}`}>
      {src && (
        // eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web
        <img src={src} alt="" className="size-full [image-rendering:pixelated]" />
      )}
    </span>
  )
}

/** The person's own work: always there, paid by the hour, whoever else is out. */
function TrainerCard({
  work,
  busy,
  act,
}: {
  work: Started
  busy: boolean
  act: (a: WorkAction) => void
}) {
  const { trainer, rules } = work
  const toBonus = rules.bonus_every_hours - trainer.hours_to_bonus
  return (
    <section className="border-line flex flex-wrap items-center gap-x-8 gap-y-4 rounded-lg border p-5">
      <div className="flex min-w-0 flex-1 flex-col gap-2">
        <p className="flex items-center gap-2">
          <span className="font-medium">나의 일</span>
          <TypeChip id="normal" name="노말" />
        </p>
        <p className="text-muted text-xs">
          코딩한 시간마다 {points(rules.points_per_hour)}, {rules.bonus_every_hours}시간마다 보너스{' '}
          {points(rules.bonus_points)} 를 받습니다.
        </p>
        <div className="max-w-sm space-y-1.5">
          <p className="text-muted flex justify-between text-xs">
            <span>
              보너스까지 <span className="font-mono tabular-nums">{trainer.hours_to_bonus}</span>
              시간
            </span>
            <span className="font-mono tabular-nums">
              {toBonus} / {rules.bonus_every_hours}
            </span>
          </p>
          <ProgressBar value={toBonus} max={rules.bonus_every_hours} label="보너스까지" />
        </div>
      </div>
      <div className="flex items-center gap-4">
        <p className="text-right">
          <span className="text-muted block text-xs">받을 포인트</span>
          <span className="font-mono text-lg font-medium tabular-nums">
            {points(trainer.points_waiting)}
          </span>
        </p>
        <button
          type="button"
          className={trainer.points_waiting > 0 ? primary : quiet}
          disabled={busy || trainer.points_waiting === 0}
          onClick={() => act({ fn: 'settle_trainer' })}
        >
          받기
        </button>
      </div>
    </section>
  )
}

/** How many of the best-paid are offered before the rest are asked for. */
const SHOWN = 3

/** Pick who goes: the best-paid few as rows to choose from, the rest on request. */
function Picker({
  place,
  work,
  busy,
  act,
}: {
  place: Workplace
  work: Started
  busy: boolean
  act: (a: WorkAction) => void
}) {
  // Those not out on a request already, best paid first: a Pokémon stays
  // until its request is done.
  const candidates = work.pokemon
    .filter((p) => p.workplace_id === null)
    .map((p) => ({ p, offer: p.offers.find((o) => o.workplace_id === place.id)! }))
    .sort((a, b) => b.offer.points - a.offer.points)
  const [chosen, setChosen] = useState('')
  const [all, setAll] = useState(false)
  const picked = candidates.find((c) => c.p.id === chosen) ?? candidates[0]

  if (!picked) {
    return (
      <p className="text-muted text-sm">
        보낼 수 있는 포켓몬이 없습니다. Lv.{work.rules.min_work_level} 이상이고 다른 의뢰를 하고
        있지 않은 포켓몬이 갈 수 있습니다.
      </p>
    )
  }
  const shown = all ? candidates : candidates.slice(0, SHOWN)
  return (
    <div className="space-y-3">
      <ul role="radiogroup" aria-label="보낼 포켓몬" className="space-y-1.5">
        {shown.map(({ p, offer }) => (
          <li key={p.id}>
            <button
              type="button"
              role="radio"
              aria-checked={p.id === picked.p.id}
              onClick={() => setChosen(p.id)}
              className="border-line hover:border-line-strong aria-checked:border-ink aria-checked:bg-surface-raised flex w-full items-center gap-3 rounded-md border px-2 py-1 text-left"
            >
              <Sprite src={spriteUrl(p, 'small')} size="sm" />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-medium">
                  {p.is_shiny && <span title="색이 다른 포켓몬">✨</span>}
                  {ko(p)} <span className="text-muted font-mono text-xs">Lv.{p.level}</span>
                </span>
                <span className="text-muted block text-xs">{aptitudeLine(offer.aptitude)}</span>
              </span>
              <span className="font-mono text-sm tabular-nums">{points(offer.points)}</span>
            </button>
          </li>
        ))}
      </ul>
      {candidates.length > SHOWN && (
        <button
          type="button"
          onClick={() => setAll(!all)}
          className="text-accent hover:text-ink text-xs"
        >
          {all ? '접기' : `모두 보기 (${candidates.length})`}
        </button>
      )}
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <button
          type="button"
          className={primary}
          disabled={busy}
          onClick={() => act({ fn: 'assign', workplace_id: place.id, companion_id: picked.p.id })}
        >
          {ko(picked.p)} 보내기
        </button>
        <span className="text-muted text-xs">의뢰를 마칠 때까지 돌아오지 않습니다.</span>
      </div>
    </div>
  )
}

function RequestCard({
  place,
  work,
  busy,
  act,
}: {
  place: Workplace
  work: Started
  busy: boolean
  act: (a: WorkAction) => void
}) {
  const shift = work.rules.shift_hours
  const client = place.client
  const worker = place.worker
    ? work.pokemon.find((p) => p.id === place.worker!.companion_id)
    : undefined

  return (
    <li className="border-line flex flex-col rounded-lg border">
      <header className="flex items-center gap-4 px-5 pt-5 pb-4">
        <Sprite
          src={spriteUrl({ sprites: client.sprites, is_shiny: false, gender: null }, 'small')}
          size="lg"
        />
        <div className="flex min-w-0 flex-1 flex-col gap-1.5">
          <p className="flex items-baseline justify-between gap-2">
            <span className="font-medium">
              <a
                href={`${env.NEXT_PUBLIC_POKEDEX_URL}/national/${client.species_id}`}
                className="hover:text-accent"
              >
                {ko(client)}
              </a>
              의 {ko(place.task)}
            </span>
            <span className="text-muted font-mono text-xs">
              No.{String(client.species_id).padStart(3, '0')}
            </span>
          </p>
          <p className="flex gap-1">
            {place.types.map((t) => (
              <TypeChip key={t.id} id={t.id} name={ko(t)} />
            ))}
          </p>
          <p className="text-muted text-xs">
            {place.types.map((t) => ko(t)).join('·')} 타입에 강한 포켓몬을 찾고 있다.
          </p>
        </div>
      </header>

      <div className="border-line flex flex-1 flex-col gap-4 border-t px-5 py-4">
        {place.worker && worker ? (
          <>
            <div className="flex items-center gap-3">
              <Sprite src={spriteUrl(worker, 'small')} size="md" />
              <div className="min-w-0 flex-1">
                <Link
                  href={`/box/${worker.id}`}
                  className="hover:text-accent block truncate text-sm font-medium"
                >
                  {worker.is_shiny && <span title="색이 다른 포켓몬">✨</span>}
                  {ko(worker)}{' '}
                  <span className="text-muted font-mono text-xs">Lv.{worker.level}</span>
                </Link>
                <p className="text-muted text-xs">{aptitudeLine(place.worker.aptitude)}</p>
              </div>
              <p className="text-right">
                <span className="text-muted block text-xs">보상</span>
                <span className="font-mono text-sm font-medium tabular-nums">
                  {points(place.worker.points)}
                </span>
              </p>
            </div>
            <div className="space-y-1.5">
              <p className="text-muted flex justify-between text-xs">
                <span>
                  <span className="font-mono tabular-nums">
                    {place.worker.hours} / {shift}
                  </span>
                  시간
                </span>
                {!place.worker.can_settle && (
                  <span>
                    <span className="font-mono tabular-nums">{shift - place.worker.hours}</span>
                    시간 남음
                  </span>
                )}
              </p>
              <ProgressBar value={place.worker.hours} max={shift} label="의뢰를 마칠 때까지" />
            </div>
            {place.worker.can_settle && (
              <div className="mt-auto">
                <button
                  type="button"
                  className={primary}
                  disabled={busy}
                  onClick={() => act({ fn: 'settle', workplace_id: place.id })}
                >
                  보상 받기
                </button>
              </div>
            )}
          </>
        ) : (
          <Picker place={place} work={work} busy={busy} act={act} />
        )}
      </div>

      {!place.worker && (
        <footer className="border-line text-muted flex min-h-12 items-center justify-between gap-3 border-t px-5 py-2 text-xs">
          {place.can_reroll ? (
            <>
              <span>다른 의뢰로 바꿀 수 있습니다.</span>
              <button
                type="button"
                className="text-accent hover:text-ink font-medium"
                disabled={busy}
                onClick={() => act({ fn: 'reroll', workplace_id: place.id })}
              >
                다른 의뢰 찾기
              </button>
            </>
          ) : (
            <span>
              <span className="font-mono tabular-nums">
                {shift - Math.min(place.hours_open, shift)}
              </span>
              시간 뒤 다른 의뢰로 바꿀 수 있습니다
            </span>
          )}
        </footer>
      )}
    </li>
  )
}

export function RequestsView() {
  const { work, failure, busy, last, act } = useWork()
  const sinceSync = useHoursSinceSync()
  const message = last ? say(last.action, last.outcome) : null

  if (!work) {
    return failure ? (
      <p className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">{failure}</p>
    ) : (
      <p className="text-muted text-sm">불러오는 중…</p>
    )
  }
  if (!work.started) {
    return (
      <p className="text-muted text-sm">
        아직 알을 받지 않았습니다.{' '}
        <Link href="/" className="text-accent">
          대시보드에서 시작하세요
        </Link>
      </p>
    )
  }

  const out = work.workplaces.filter((w) => w.worker).length
  const ready = work.workplaces.filter((w) => w.worker?.can_settle).length

  return (
    <>
      <div className="flex items-baseline justify-between gap-3">
        <div className="flex items-baseline gap-3">
          <h1 className="text-2xl font-semibold tracking-tight">의뢰</h1>
          <span className="text-muted text-xs">
            진행 중{' '}
            <span className="font-mono tabular-nums">
              {out} / {work.workplaces.length}
            </span>
            {ready > 0 && (
              <>
                {' · 끝난 의뢰 '}
                <span className="font-mono tabular-nums">{ready}</span>
              </>
            )}
          </span>
        </div>
        <span className="font-mono text-sm tabular-nums">{points(work.points)}</span>
      </div>
      {failure && (
        <p className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">{failure}</p>
      )}
      {message && <p className="bg-accent/10 rounded-md px-3 py-2 text-sm">{message}</p>}

      <TrainerCard work={work} busy={busy} act={act} />

      <ul className="grid gap-3 sm:grid-cols-2">
        {work.workplaces.map((place) => (
          <RequestCard key={place.id} place={place} work={work} busy={busy} act={act} />
        ))}
      </ul>

      <div className="text-muted max-w-2xl space-y-2 text-xs">
        <p>
          시간은 코딩 에이전트를 쓴 시간만 셉니다. 포켓몬이 {work.rules.shift_hours}시간을 일하면
          보상을 받을 수 있고, 받으면 새 의뢰가 들어옵니다. 아무도 보내지 않은 의뢰는{' '}
          {work.rules.shift_hours}시간이 지나면 다른 의뢰로 바꿀 수 있습니다. 의뢰한 포켓몬의 타입에
          효과가 좋은 타입일수록, 레벨이 높을수록 보상이 큽니다.
        </p>
        {sinceSync !== null && sinceSync >= 2 && (
          <>
            <p>
              마지막 동기화가 {sinceSync}시간 전입니다. 그동안 코딩했는데 시간이 늘지 않았다면 그
              기기에서 이것을 실행해 보세요.
            </p>
            <Command command="pokegosu coder hook doctor" />
          </>
        )}
      </div>
    </>
  )
}
