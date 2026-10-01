'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'
import { Command } from '@pokegosu/ui/command'
import { PokeGosuIcon } from '@pokegosu/ui/icon'
import { ProgressBar, TypeChip } from '@pokegosu/ui/pokemon'
import { Toast } from '@pokegosu/ui/toast'

import { env } from '@/env'
import { exactTokens, points } from '@/lib/format'
import { josa } from '@/lib/josa'
import { aptitudeLine, ko, spriteUrl, type Named, type Work, type Workplace } from '@/lib/game'

import { useWork, type WorkAction, type WorkLast } from '../game/use-work'

type Started = Extract<Work, { started: true }>
type Act = (a: WorkAction) => void

const primary =
  'bg-accent text-surface rounded-md px-3.5 py-2 text-sm font-medium disabled:opacity-50'

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

function say({ action, outcome: o, before }: WorkLast): string | null {
  const started = before?.started ? before : null
  const pokemon = (id: string | undefined) => {
    const found = started?.pokemon.find((p) => p.id === id)
    return found ? ko(found) : '포켓몬'
  }
  switch (`${action.fn}:${o.outcome}`) {
    case 'settle:settled': {
      const place = started?.workplaces.find(
        (w) => 'workplace_id' in action && w.id === action.workplace_id,
      )
      return `${josa(pokemon(place?.worker?.companion_id), '이')} 의뢰를 마치고 ${exactTokens(Number(o.points))} 포인트를 받았다!`
    }
    case 'settle_trainer:settled':
      return `${josa(started?.trainer.name ?? '트레이너', '이')} ${exactTokens(Number(o.points) + Number(o.bonus))} 포인트를 받았다!`
    case 'reroll:rerolled':
      return '의뢰를 거절했다.'
    case 'assign:assigned':
      return `${josa(pokemon(action.fn === 'assign' ? action.companion_id : undefined), '이')} 의뢰를 하러 떠났다.`
    default:
      return null
  }
}

function Sprite({ src, size }: { src: string | undefined; size: 40 | 56 }) {
  return src ? (
    // eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web
    <img
      src={src}
      alt=""
      width={size}
      height={size}
      className="flex-none [image-rendering:pixelated]"
    />
  ) : (
    <span style={{ width: size, height: size }} className="flex-none" />
  )
}

/** A number in the mono face, beside words in the sans. */
function N({ children }: { children: React.ReactNode }) {
  return <span className="font-mono tabular-nums">{children}</span>
}

/** A request as a notice: who asks, for what, what it pays, and who is on it. */
function Notice({
  dashed,
  who,
  title,
  art,
  wanted,
  rewardLabel,
  reward,
  status,
  footer,
}: {
  dashed: boolean
  who: React.ReactNode
  title: string
  art: React.ReactNode
  wanted: React.ReactNode
  rewardLabel: string
  reward: number
  status: React.ReactNode
  footer: React.ReactNode
}) {
  return (
    <li
      className={`flex flex-col gap-3.5 rounded-lg border p-5 ${dashed ? 'border-line-strong border-dashed' : 'border-line'}`}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex min-w-0 flex-col gap-1">
          <span className="text-muted text-xs">{who}</span>
          <span className="text-lg font-semibold tracking-tight">{title}</span>
        </div>
        {art}
      </div>
      <p className="flex flex-wrap items-center gap-1 text-[13px]">{wanted}</p>
      <p className="flex items-baseline gap-2">
        <span className="text-muted text-xs">{rewardLabel}</span>
        <span className="font-mono text-[22px] font-medium tabular-nums">{points(reward)}</span>
      </p>
      {status}
      {/* As tall as the picker's button, so the rule sits level across notices
          whatever the footer holds. */}
      <div className="border-line mt-auto flex min-h-[42px] items-center gap-2 border-t pt-3 [box-sizing:content-box]">
        {footer}
      </div>
    </li>
  )
}

/** Hours so far against the whole, with what the bar stands for above it. */
function Progress({
  left,
  value,
  max,
  label,
}: {
  left: React.ReactNode
  value: number
  max: number
  label: string
}) {
  return (
    <div className="space-y-1.5">
      <p className="text-muted flex justify-between text-xs">
        <span>{left}</span>
        <N>
          {value} / {max}
        </N>
      </p>
      <ProgressBar value={value} max={max} label={label} />
    </div>
  )
}

function Chips({ types }: { types: ({ id: string } & Named)[] }) {
  return (
    <>
      {types.map((t) => (
        <TypeChip key={t.id} id={t.id} name={ko(t)} />
      ))}
    </>
  )
}

/** Gosu's own request, always there: the person codes, and is paid by the hour. */
function GosuNotice({ work, busy, act }: { work: Started; busy: boolean; act: Act }) {
  const { trainer, rules } = work
  return (
    <Notice
      dashed={false}
      who="고수의 의뢰"
      title="코딩"
      art={
        <span className="grid size-14 flex-none place-items-center">
          <PokeGosuIcon size={44} />
        </span>
      }
      wanted={
        <>
          구함 <TypeChip id="normal" name="노말" /> 코딩하는 트레이너
        </>
      }
      rewardLabel="받을 보상"
      reward={trainer.points_waiting}
      status={
        <Progress
          left={
            <>
              보너스 {points(rules.bonus_points)} 까지 <N>{trainer.hours_to_bonus}</N>시간
            </>
          }
          value={rules.bonus_every_hours - trainer.hours_to_bonus}
          max={rules.bonus_every_hours}
          label="보너스까지"
        />
      }
      footer={
        <>
          <span className="min-w-0 flex-1 text-[13px]">
            <span className="block truncate">{trainer.name ?? '트레이너'}</span>
            <span className="text-muted block text-xs">
              코딩한 시간마다 {points(rules.points_per_hour)}
            </span>
          </span>
          {trainer.points_waiting > 0 && (
            <button
              type="button"
              className={primary}
              disabled={busy}
              onClick={() => act({ fn: 'settle_trainer' })}
            >
              받기
            </button>
          )}
        </>
      }
    />
  )
}

/**
 * Who goes: the choice as a button that opens the list, best paid first. A
 * Pokémon already out on a request is not offered: it stays until done. Nor
 * is the partner: tokens raise it, so it stays home.
 */
function Picker({
  place,
  work,
  busy,
  act,
  onPick,
}: {
  place: Workplace
  work: Started
  busy: boolean
  act: Act
  onPick: (points: number) => void
}) {
  const candidates = work.pokemon
    .filter((p) => p.workplace_id === null && !p.is_main)
    .map((p) => ({ p, offer: p.offers.find((o) => o.workplace_id === place.id)! }))
    .sort((a, b) => b.offer.points - a.offer.points)
  const [chosen, setChosen] = useState('')
  const [open, setOpen] = useState(false)
  const picked = candidates.find((c) => c.p.id === chosen) ?? candidates[0]
  const offered = picked?.offer.points ?? 0
  useEffect(() => onPick(offered), [offered, onPick])

  if (!picked) {
    return (
      <p className="text-muted text-xs">
        <span
          className="cursor-help underline decoration-dotted underline-offset-2"
          title={[
            '보낼 수 있는 포켓몬',
            `- Lv.${work.rules.min_work_level} 이상`,
            '- 파트너가 아님',
            '- 다른 의뢰를 하고 있지 않음',
          ].join('\n')}
        >
          보낼 수 있는 포켓몬
        </span>
        이 없습니다.
      </p>
    )
  }
  return (
    <div
      className="relative flex w-full items-center gap-2"
      // The list closes when focus leaves it, or on Escape, as a menu does.
      onBlur={(e) => {
        if (!e.currentTarget.contains(e.relatedTarget)) setOpen(false)
      }}
      onKeyDown={(e) => {
        if (e.key === 'Escape') setOpen(false)
      }}
    >
      <button
        type="button"
        aria-label="보낼 포켓몬"
        aria-expanded={open}
        onClick={() => setOpen(!open)}
        className="border-line-strong hover:border-ink flex min-w-0 flex-1 items-center gap-2 rounded-md border pr-2 text-left"
      >
        <Sprite src={spriteUrl(picked.p, 'small')} size={40} />
        <span className="min-w-0 flex-1 truncate text-[13px]">
          {ko(picked.p)} <span className="text-muted font-mono text-xs">Lv.{picked.p.level}</span>
        </span>
        <span aria-hidden="true" className="text-muted text-xs">
          ▾
        </span>
      </button>
      <button
        type="button"
        className={primary}
        disabled={busy}
        onClick={() => act({ fn: 'assign', workplace_id: place.id, companion_id: picked.p.id })}
      >
        보내기
      </button>
      {open && (
        <ul
          role="listbox"
          aria-label="보낼 포켓몬"
          className="border-line bg-surface absolute right-0 bottom-full left-0 z-10 mb-2 max-h-72 overflow-y-auto rounded-lg border p-1"
        >
          {candidates.map(({ p, offer }) => (
            <li key={p.id}>
              <button
                type="button"
                role="option"
                aria-selected={p.id === picked.p.id}
                onClick={() => {
                  setChosen(p.id)
                  setOpen(false)
                }}
                className="aria-selected:bg-surface-raised hover:bg-surface-raised flex w-full items-center gap-2 rounded-md pr-2 text-left"
              >
                <Sprite src={spriteUrl(p, 'small')} size={40} />
                <span className="min-w-0 flex-1">
                  <span className="block truncate text-[13px] font-medium">
                    {p.is_shiny && <span title="색이 다른 포켓몬">✨</span>}
                    {ko(p)} <span className="text-muted font-mono text-xs">Lv.{p.level}</span>
                  </span>
                  <span className="text-muted block text-xs">{aptitudeLine(offer.aptitude)}</span>
                </span>
                <span className="font-mono text-[13px] tabular-nums">{points(offer.points)}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

/** The slot of a request turned down, until the next one arrives. */
function Waiting({ hours, shift }: { hours: number; shift: number }) {
  return (
    <li className="border-line text-muted flex flex-col justify-center gap-3.5 rounded-lg border border-dashed p-5">
      <span className="text-ink text-lg font-semibold tracking-tight">새 의뢰를 기다리는 중</span>
      <Progress
        left={
          <>
            <N>{hours}</N>시간 남음
          </>
        }
        value={shift - hours}
        max={shift}
        label="다음 의뢰까지"
      />
    </li>
  )
}

function RequestNotice({
  place,
  work,
  busy,
  act,
}: {
  place: Workplace
  work: Started
  busy: boolean
  act: Act
}) {
  const shift = work.rules.shift_hours
  const [offered, setOffered] = useState(0)
  if (!place.arrived) return <Waiting hours={place.hours_to_arrive} shift={shift} />
  const client = place.client
  const worker = place.worker
    ? work.pokemon.find((p) => p.id === place.worker!.companion_id)
    : undefined

  const who = (
    <>
      <a
        href={`${env.NEXT_PUBLIC_POKEDEX_URL}/national/${client.species_id}`}
        className="text-muted hover:text-ink"
      >
        {ko(client)}
      </a>
      의 의뢰 · <N>No.{String(client.species_id).padStart(3, '0')}</N>
    </>
  )
  const art = (
    <Sprite
      src={spriteUrl({ sprites: client.sprites, is_shiny: false, gender: null }, 'small')}
      size={56}
    />
  )
  const wanted = (
    <>
      구함 <Chips types={place.types} /> 에 강한 포켓몬
    </>
  )

  if (place.worker && worker) {
    const done = place.worker.can_settle
    return (
      <Notice
        dashed={false}
        who={who}
        title={ko(place.task)}
        art={art}
        wanted={wanted}
        rewardLabel="보상"
        reward={place.worker.points}
        status={
          <Progress
            left={
              done ? (
                '의뢰를 마쳤다!'
              ) : (
                <>
                  <N>{shift - place.worker.hours}</N>시간 남음
                </>
              )
            }
            value={place.worker.hours}
            max={shift}
            label="의뢰를 마칠 때까지"
          />
        }
        footer={
          <>
            <Sprite src={spriteUrl(worker, 'small')} size={40} />
            <Link href={`/box/${worker.id}`} className="group min-w-0 flex-1 text-[13px]">
              <span className="group-hover:text-accent block truncate">
                {worker.is_shiny && <span title="색이 다른 포켓몬">✨</span>}
                {ko(worker)} <span className="text-muted font-mono text-xs">Lv.{worker.level}</span>
              </span>
              <span className="text-muted block text-xs">
                {aptitudeLine(place.worker.aptitude)}
              </span>
            </Link>
            {done ? (
              <button
                type="button"
                className={primary}
                disabled={busy}
                onClick={() => act({ fn: 'settle', workplace_id: place.id })}
              >
                보상 받기
              </button>
            ) : (
              <span className="text-muted text-xs">일하는 중</span>
            )}
          </>
        }
      />
    )
  }

  return (
    <Notice
      dashed
      who={who}
      title={ko(place.task)}
      art={art}
      wanted={wanted}
      rewardLabel="보상"
      reward={offered}
      status={
        <p className="text-muted text-xs">
          도와줄 포켓몬을 기다리고 있다 ·{' '}
          <button
            type="button"
            className="text-accent hover:text-ink"
            disabled={busy}
            onClick={() => act({ fn: 'reroll', workplace_id: place.id })}
          >
            거절하기
          </button>
        </p>
      }
      footer={<Picker place={place} work={work} busy={busy} act={act} onPick={setOffered} />}
    />
  )
}

export function RequestsView() {
  const { work, failure, busy, last, act } = useWork()
  const sinceSync = useHoursSinceSync()
  const message = last ? say(last) : null

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
            <N>
              {out} / {work.workplaces.length}
            </N>
            {ready > 0 && (
              <>
                {' · 끝난 의뢰 '}
                <N>{ready}</N>
              </>
            )}
          </span>
        </div>
        <span className="font-mono text-sm tabular-nums">{points(work.points)}</span>
      </div>
      {failure && (
        <p className="bg-danger-surface text-danger rounded-md px-3 py-2 text-sm">{failure}</p>
      )}
      <Toast id={last}>{message}</Toast>

      <ul className="grid gap-3 sm:grid-cols-3">
        <GosuNotice work={work} busy={busy} act={act} />
        {work.workplaces.map((place) => (
          <RequestNotice key={place.id} place={place} work={work} busy={busy} act={act} />
        ))}
      </ul>

      {sinceSync !== null && sinceSync >= 2 && (
        <div className="text-muted max-w-2xl space-y-2 text-xs">
          <p>
            마지막 동기화가 <N>{sinceSync}</N>시간 전입니다. 그동안 코딩했는데 시간이 늘지 않았다면
            그 기기에서 이것을 실행해 보세요.
          </p>
          <Command command="pokegosu coder hook doctor" />
        </div>
      )}
    </>
  )
}
