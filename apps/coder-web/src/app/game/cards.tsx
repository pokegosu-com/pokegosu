'use client'

import { exactTokens } from '@/lib/format'
import {
  MARKS,
  cycleMark,
  eggHint,
  eggSpriteUrl,
  ko,
  markOf,
  spriteUrl,
  type Egg,
  type Pokemon,
} from '@/lib/game'

import type { useGame } from './use-game'

type Act = ReturnType<typeof useGame>['act']

const button =
  'rounded-md px-3 py-1.5 text-xs font-medium disabled:opacity-50 bg-accent text-surface'
const quiet =
  'rounded-md px-3 py-1.5 text-xs font-medium disabled:opacity-50 border border-muted/40 hover:border-muted'

function Bar({ value, max }: { value: number; max: number }) {
  const share = max > 0 ? Math.min(1, value / max) : 1
  return (
    <span className="bg-muted/15 block h-1.5 overflow-hidden rounded-full">
      <span className="bg-accent block h-full rounded-full" style={{ width: `${share * 100}%` }} />
    </span>
  )
}

export function Marks({
  markings,
  onChange,
  disabled,
}: {
  markings: number
  onChange: (markings: number) => void
  disabled: boolean
}) {
  return (
    <span className="flex gap-1 text-sm leading-none">
      {MARKS.map((mark, i) => {
        const color = markOf(markings, i)
        return (
          <button
            key={mark}
            type="button"
            disabled={disabled}
            onClick={() => onChange(cycleMark(markings, i))}
            className={
              color === 1 ? 'text-sky-500' : color === 2 ? 'text-rose-500' : 'text-muted/40'
            }
            aria-label={`${mark} ${['끔', '파랑', '빨강'][color]}`}
          >
            {mark}
          </button>
        )
      })}
    </span>
  )
}

export function PokemonCard({
  pokemon: p,
  act,
  busy,
}: {
  pokemon: Pokemon
  act: Act
  busy: boolean
}) {
  const toNext = p.next_level_exp === null ? null : p.next_level_exp - p.exp
  return (
    <article
      className={`space-y-3 rounded-lg border px-4 py-3 ${p.is_main ? 'border-accent' : 'border-muted/25'}`}
    >
      <header className="flex items-start gap-3">
        {/* eslint-disable-next-line @next/next/no-img-element -- animated GIFs from pokedex-web */}
        <img src={spriteUrl(p)} alt={ko(p.names)} className="h-16 w-16 object-contain" />
        <div className="min-w-0 flex-1 space-y-1">
          <p className="flex items-center gap-1 font-medium">
            {p.is_shiny && <span title="색이 다른 포켓몬">✨</span>}
            {ko(p.names)}
            <span className="text-muted text-xs tabular-nums">
              No.{String(p.dex_no).padStart(3, '0')}
            </span>
            {p.is_main && <span className="text-accent ml-auto text-xs">메인</span>}
          </p>
          <p className="text-muted flex gap-1 text-xs">
            {p.types.map((t) => (
              <span key={t.id} className="border-muted/30 rounded border px-1">
                {ko(t.names)}
              </span>
            ))}
          </p>
          <Marks
            markings={p.markings}
            disabled={busy}
            onChange={(markings) => act({ fn: 'set_markings', companion_id: p.id, markings })}
          />
        </div>
      </header>

      <div className="space-y-1">
        <p className="flex justify-between text-xs">
          <span className="tabular-nums">Lv.{p.level}</span>
          <span className="text-muted tabular-nums">
            {toNext === null ? '최고 레벨' : `다음 레벨까지 ${exactTokens(toNext)} 경험치`}
          </span>
        </p>
        <Bar value={p.exp - p.level_exp} max={(p.next_level_exp ?? p.exp) - p.level_exp} />
        {p.evolves_to && !p.can_evolve && (
          <p className="text-muted text-xs">
            Lv.{p.evolves_to.level} 에 {ko(p.evolves_to.names)}(으)로 진화할 수 있다
          </p>
        )}
      </div>

      {p.ribbons.length > 0 && (
        <p className="flex flex-wrap gap-1 text-xs">
          {p.ribbons.map((r) => (
            <span key={r.id} className="rounded bg-amber-500/15 px-1.5 py-0.5">
              🎀 {ko(r.names)}
            </span>
          ))}
        </p>
      )}

      <footer className="flex flex-wrap gap-2">
        {p.can_evolve && p.evolves_to && (
          <button
            type="button"
            className={button}
            disabled={busy}
            onClick={() => act({ fn: 'evolve', companion_id: p.id })}
          >
            {ko(p.evolves_to.names)}(으)로 진화
          </button>
        )}
        {p.can_receive_egg && (
          <button
            type="button"
            className={button}
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
            className={button}
            disabled={busy}
            onClick={() => act({ fn: 'receive_ribbon', companion_id: p.id, ribbon_id: r.id })}
          >
            {ko(r.names)} 받기
          </button>
        ))}
        {!p.is_main && (
          <button
            type="button"
            className={quiet}
            disabled={busy}
            onClick={() => act({ fn: 'set_main', companion_id: p.id })}
          >
            메인으로
          </button>
        )}
      </footer>
    </article>
  )
}

export function EggCard({ egg, act, busy }: { egg: Egg; act: Act; busy: boolean }) {
  const ready = egg.steps >= egg.steps_needed
  return (
    <article
      className={`space-y-3 rounded-lg border px-4 py-3 ${egg.is_main ? 'border-accent' : 'border-muted/25'}`}
    >
      <header className="flex items-start gap-3">
        {/* eslint-disable-next-line @next/next/no-img-element -- served by pokedex-web */}
        <img
          src={eggSpriteUrl}
          alt="알"
          className="h-16 w-16 object-contain [image-rendering:pixelated]"
        />
        <div className="min-w-0 flex-1 space-y-1">
          <p className="flex items-center font-medium">
            알{egg.is_main && <span className="text-accent ml-auto text-xs">메인</span>}
          </p>
          <p className="text-muted text-xs">{eggHint(egg)}</p>
          <Marks
            markings={egg.markings}
            disabled={busy}
            onChange={(markings) => act({ fn: 'set_markings', companion_id: egg.id, markings })}
          />
        </div>
      </header>

      <div className="space-y-1">
        <p className="text-muted text-right text-xs tabular-nums">
          {exactTokens(egg.steps)} / {exactTokens(egg.steps_needed)} 걸음
        </p>
        <Bar value={egg.steps} max={egg.steps_needed} />
      </div>

      <footer className="flex flex-wrap gap-2">
        {ready && (
          <button
            type="button"
            className={button}
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
            메인으로
          </button>
        )}
      </footer>
    </article>
  )
}
