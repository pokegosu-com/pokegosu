'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'
import { Command } from '@pokegosu/ui/command'
import { ProgressBar, TypeChip } from '@pokegosu/ui/pokemon'

import { points } from '@/lib/format'
import { aptitudeLine, ko, spriteUrl, type Work, type Workplace } from '@/lib/game'

import type { Outcome } from '../game/use-game'
import { useWork, type WorkAction } from '../game/use-work'

type Started = Extract<Work, { started: true }>

const primary =
  'bg-accent text-surface rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50'
const quiet =
  'border-line-strong hover:border-ink rounded-md border px-4 py-2 text-sm font-medium disabled:opacity-50'
const control =
  'border-line-strong bg-surface min-w-0 flex-1 rounded-md border px-2.5 py-1.5 text-[13px] focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent'

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
      return `${points(Number(o.points))} 를 벌어 왔다!`
    case 'settle_trainer:settled':
      return Number(o.bonus) > 0
        ? `${points(Number(o.points))} 와 보너스 ${points(Number(o.bonus))} 를 받았다!`
        : `${points(Number(o.points))} 를 받았다!`
    case 'reroll:rerolled':
      return '새 업장을 찾았다.'
    default:
      return null
  }
}

function Types({ types }: { types: Workplace['types'] }) {
  return (
    <span className="flex gap-1">
      {types.map((t) => (
        <TypeChip key={t.id} id={t.id} name={ko(t)} />
      ))}
    </span>
  )
}

/** The person's own workplace: always Normal, always there, paid by the hour. */
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
  return (
    <section className="border-line flex flex-wrap items-center gap-x-6 gap-y-3 rounded-lg border p-5">
      <div className="flex min-w-0 flex-1 flex-col gap-1.5">
        <p className="flex items-center gap-2">
          <span className="font-medium">나의 업장</span>
          <TypeChip id="normal" name="노말" />
        </p>
        <p className="text-muted text-xs">
          활동한 시간마다 {points(rules.points_per_hour)}, {rules.bonus_every_hours}시간마다{' '}
          {points(rules.bonus_points)} 를 더 받습니다.
        </p>
        <p className="text-muted font-mono text-xs tabular-nums">
          {trainer.hours}시간 활동 · 보너스까지 {trainer.hours_to_bonus}시간
        </p>
      </div>
      <p className="font-mono text-sm tabular-nums">{points(trainer.points_waiting)}</p>
      <button
        type="button"
        className={trainer.points_waiting > 0 ? primary : quiet}
        disabled={busy || trainer.points_waiting === 0}
        onClick={() => act({ fn: 'settle_trainer' })}
      >
        정산
      </button>
    </section>
  )
}

function WorkplaceCard({
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
  const worker = place.worker
    ? work.pokemon.find((p) => p.id === place.worker!.companion_id)
    : undefined
  // Those not at work already, best paid first: a Pokémon stays where it was
  // sent until its shift is settled.
  const candidates = work.pokemon
    .filter((p) => p.workplace_id === null)
    .map((p) => ({ p, offer: p.offers.find((o) => o.workplace_id === place.id)! }))
    .sort((a, b) => b.offer.points - a.offer.points)
  const [chosen, setChosen] = useState('')
  const picked = candidates.find((c) => c.p.id === chosen) ?? candidates[0]

  return (
    <li className="border-line flex flex-col gap-4 rounded-lg border p-5">
      <p className="flex items-center justify-between gap-2">
        <Types types={place.types} />
        <span className="text-muted font-mono text-xs">업장 {place.slot}</span>
      </p>

      {place.worker && worker ? (
        <>
          <div className="flex items-center gap-3">
            <span className="bg-surface-raised grid size-16 flex-none place-items-center rounded-md">
              {/* eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web */}
              <img
                src={spriteUrl(worker, 'small')}
                alt=""
                className="size-16 [image-rendering:pixelated]"
              />
            </span>
            <div className="min-w-0 space-y-0.5">
              <Link href={`/box/${worker.id}`} className="hover:text-accent text-sm font-medium">
                {worker.is_shiny && <span title="색이 다른 포켓몬">✨</span>}
                {ko(worker)} <span className="text-muted font-mono text-xs">Lv.{worker.level}</span>
              </Link>
              <p className="text-muted text-xs">{aptitudeLine(place.worker.aptitude)}</p>
            </div>
          </div>
          <div className="space-y-1.5">
            <p className="text-muted flex justify-between font-mono text-xs tabular-nums">
              <span>
                {place.worker.hours} / {shift}시간
              </span>
              <span>{points(place.worker.points)}</span>
            </p>
            <ProgressBar value={place.worker.hours} max={shift} label="정산까지" />
          </div>
          <div className="flex gap-2">
            <button
              type="button"
              className={place.worker.can_settle ? primary : quiet}
              disabled={busy || !place.worker.can_settle}
              onClick={() => act({ fn: 'settle', workplace_id: place.id })}
            >
              정산
            </button>
          </div>
        </>
      ) : (
        <>
          {picked ? (
            <div className="space-y-2">
              <div className="flex gap-2">
                <select
                  aria-label="보낼 포켓몬"
                  value={picked.p.id}
                  onChange={(e) => setChosen(e.target.value)}
                  className={control}
                >
                  {candidates.map(({ p, offer }) => (
                    <option key={p.id} value={p.id}>
                      {ko(p)} Lv.{p.level} · {points(offer.points)}
                    </option>
                  ))}
                </select>
                <button
                  type="button"
                  className={primary}
                  disabled={busy}
                  onClick={() =>
                    act({ fn: 'assign', workplace_id: place.id, companion_id: picked.p.id })
                  }
                >
                  보내기
                </button>
              </div>
              <p className="text-muted text-xs">
                {ko(picked.p)}은(는) {aptitudeLine(picked.offer.aptitude)}. 보내면 정산할 때까지
                돌아오지 않습니다.
              </p>
            </div>
          ) : (
            <p className="text-muted text-sm">
              보낼 수 있는 포켓몬이 없습니다. Lv.{work.rules.min_work_level} 이상이고 다른 업장에
              있지 않은 포켓몬이 일할 수 있습니다.
            </p>
          )}
          <div className="flex items-center gap-3">
            <button
              type="button"
              className={quiet}
              disabled={busy || !place.can_reroll}
              onClick={() => act({ fn: 'reroll', workplace_id: place.id })}
            >
              다른 업장 찾기
            </button>
            {!place.can_reroll && (
              <span className="text-muted font-mono text-xs tabular-nums">
                {Math.min(place.hours_open, shift)} / {shift}시간
              </span>
            )}
          </div>
        </>
      )}
    </li>
  )
}

export function WorkView() {
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

  return (
    <>
      <div className="flex items-baseline justify-between gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">업장</h1>
        <span className="font-mono text-sm tabular-nums">{points(work.points)}</span>
      </div>
      {failure && (
        <p className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">{failure}</p>
      )}
      {message && <p className="bg-accent/10 rounded-md px-3 py-2 text-sm">{message}</p>}

      <TrainerCard work={work} busy={busy} act={act} />

      <ul className="grid gap-3 sm:grid-cols-2">
        {work.workplaces.map((place) => (
          <WorkplaceCard key={place.id} place={place} work={work} busy={busy} act={act} />
        ))}
      </ul>

      <div className="text-muted max-w-2xl space-y-2 text-xs">
        <p>
          시간은 코딩 에이전트를 쓴 시간만 셉니다. {work.rules.shift_hours}시간을 일하면 정산할 수
          있고, 정산하면 새 업장이 열립니다. 아무도 없는 업장은 {work.rules.shift_hours}시간이
          지나면 다른 업장으로 바꿀 수 있습니다. 포켓몬의 타입이 업장의 타입에 효과가 좋을수록,
          레벨이 높을수록 많이 벌어 옵니다.
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
