import { exactTokens } from '@/lib/format'
import { ko, type Box } from '@/lib/game'
import { josa } from '@/lib/josa'

import type { Last, Outcome } from './use-game'

function nameOf(box: Box | null, companionId: unknown): string {
  const found = box?.started ? box.pokemon.find((p) => p.id === companionId) : undefined
  return found ? ko(found) : '포켓몬'
}

function speciesName(box: Box | null, speciesId: unknown): string {
  const found = box?.started ? box.pokemon.find((p) => p.species_id === speciesId) : undefined
  return found ? ko(found) : '포켓몬'
}

/**
 * One line for what the last button did, in the games' voice where they have
 * one. `bought` names what a shop item is, which the box does not know.
 */
export function say(
  box: Box | null,
  last: Last,
  bought?: (shopItemId: string) => string | undefined,
) {
  const { action, outcome: o, before } = last
  const id = 'companion_id' in action ? action.companion_id : undefined
  // Every button refuses a Pokémon out on a request alike.
  if (o.outcome === 'working') return '의뢰를 하는 중이라 지금은 할 수 없다.'
  switch (`${action.fn}:${o.outcome}`) {
    case 'claim:claimed':
      // A level gained is said apart, by levelUp, once the bar reaches it.
      return o.level_before === null
        ? `알이 ${exactTokens(Number(o.tokens))} 토큰을 얻었다.`
        : `${josa(nameOf(box, id), '이')} ${exactTokens(Number(o.tokens))} 토큰을 얻었다.`
    case 'hatch:hatched':
      return `${o.is_shiny ? '✨ ' : ''}알에서 ${josa(speciesName(box, o.species_id), '이')} 태어났다!`
    case 'evolve:evolved':
    case 'use_item:evolved':
      return `${josa(nameOf(before, id), '이')} ${josa(nameOf(box, id), '으로')} 진화했다.`
    case 'receive_egg:received':
      return '알을 받았다!'
    case 'receive_ribbon:received': {
      const ribbonId = action.fn === 'receive_ribbon' ? action.ribbon_id : undefined
      const pokemon = box?.started ? box.pokemon.find((p) => p.id === id) : undefined
      const ribbon = pokemon?.ribbons.find((r) => r.id === ribbonId)
      return `${josa(ribbon ? ko(ribbon) : '리본', '을')} 받았다!`
    }
    case 'use_item:no_effect':
      return '써도 효과가 없을 것 같다.'
    case 'buy:bought': {
      const name = action.fn === 'buy' ? bought?.(action.shop_item_id) : undefined
      if (o.companion_id) return `${josa(name ?? '알', '을')} 받았다!`
      return name ? `${josa(name, '을')} 구매했다!` : '구매했다!'
    }
    case 'buy:not_enough_points':
      return '포인트가 모자랍니다.'
    case 'start_game:started':
      return '알을 받았다! 토큰을 쓰면 알이 자란다.'
    default:
      return null
  }
}

/** The level a claim took a Pokémon to, and the line that says so; null if it gained none. */
export function levelUp(
  box: Box | null,
  companionId: string,
  o: Outcome,
): { level: number; line: string } | null {
  if (o.outcome !== 'claimed' || o.level_before === null || o.level_after === o.level_before) {
    return null
  }
  const level = Number(o.level_after)
  return {
    level,
    line: `${josa(nameOf(box, companionId), '이')} 레벨 ${josa(String(level), '이')} 됐다.`,
  }
}
