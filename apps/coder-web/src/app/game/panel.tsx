'use client'

import { compactTokens, exactTokens } from '@/lib/format'
import { ko, type Box } from '@/lib/game'

import { EggCard, PokemonCard } from './cards'
import type { Outcome, useGame } from './use-game'

type Game = ReturnType<typeof useGame>

function nameOf(box: Box | null, pokedexId: unknown): string {
  const found = box?.started ? box.pokemon.find((p) => p.pokedex_id === pokedexId) : undefined
  return found ? ko(found.names) : '포켓몬'
}

/** One line for what the last button did, in the games' voice where they have one. */
function say(box: Box | null, fn: string, o: Outcome): string | null {
  switch (`${fn}:${o.outcome}`) {
    case 'claim:claimed':
      return Number(o.steps) > 0
        ? `알이 ${exactTokens(Number(o.steps))} 걸음만큼 자랐다.`
        : o.level_after !== o.level_before
          ? `경험치 ${exactTokens(Number(o.exp))} 을 얻었다! Lv.${o.level_before} → Lv.${o.level_after}`
          : `경험치 ${exactTokens(Number(o.exp))} 을 얻었다!`
    case 'hatch:hatched':
      return `${o.is_shiny ? '✨ ' : ''}알에서 ${nameOf(box, o.pokedex_id)}이(가) 태어났다!`
    case 'evolve:evolved':
      return `축하합니다! ${nameOf(box, o.to)}(으)로 진화했다!`
    case 'receive_egg:received':
      return '알을 받았다! 알 박스에 들어갔다.'
    case 'receive_ribbon:received':
      return '리본을 받았다!'
    case 'start_game:started':
      return '알을 받았다! 토큰을 쓰면 알이 자란다.'
    default:
      return null
  }
}

/** The main companion, what is left to claim, and what just happened. */
export function Panel({ game }: { game: Game }) {
  const { box, busy, last, act, failure } = game
  if (failure) {
    return <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{failure}</p>
  }
  if (!box) return <p className="text-muted text-sm">불러오는 중…</p>

  if (!box.started) {
    return (
      <section className="border-muted/25 space-y-3 rounded-lg border px-4 py-4">
        <p className="text-sm">
          지금까지 쓴 토큰{' '}
          <span className="tabular-nums">{compactTokens(BigInt(box.balance))}</span> 이 기다리고
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
    )
  }

  const main = box.pokemon.find((p) => p.is_main) ?? box.eggs.find((e) => e.is_main) ?? null
  const message = last ? say(box, last.action.fn, last.outcome) : null
  const balance = BigInt(box.balance)

  return (
    <section className="space-y-3">
      {message && <p className="bg-accent/10 rounded-md px-3 py-2 text-sm">{message}</p>}
      {main && 'pokedex_id' in main ? (
        <PokemonCard pokemon={main} act={act} busy={busy} />
      ) : main ? (
        <EggCard egg={main} act={act} busy={busy} />
      ) : null}
      <p className="text-muted flex items-center justify-between text-xs">
        <span title={`${exactTokens(box.balance)} 토큰`}>
          받을 수 있는 토큰 {balance > 0n ? compactTokens(balance) : '없음'}
        </span>
        {balance > 0n && (
          <button
            type="button"
            disabled={busy}
            onClick={() => act({ fn: 'claim', companion_id: box.main_companion_id })}
            className="border-muted/40 hover:border-muted rounded-md border px-3 py-1.5 font-medium disabled:opacity-50"
          >
            메인에게 주기
          </button>
        )}
      </p>
    </section>
  )
}
