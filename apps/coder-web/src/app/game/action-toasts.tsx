'use client'

import { Toast } from '@pokegosu/ui/toast'

import { levelUp, say } from './say'
import type { useGame } from './use-game'

/**
 * What the last action did, and, when a claim took the partner up, the level
 * it reached, said apart once the bar gets there. Where the partner's bar is
 * climbing, `level` is the level it shows; elsewhere both are said at once.
 */
export function ActionToasts({
  game,
  level,
}: {
  game: Pick<ReturnType<typeof useGame>, 'box' | 'last'>
  level?: number
}) {
  const { box, last } = game
  const up =
    last?.action.fn === 'claim' ? levelUp(box, last.action.companion_id, last.outcome) : null
  const reached = up !== null && (level === undefined || level >= up.level)
  return (
    <>
      <Toast id={last}>{last ? say(box, last.action.fn, last.outcome) : null}</Toast>
      <Toast id={reached ? last : null}>{reached ? up.line : null}</Toast>
    </>
  )
}
