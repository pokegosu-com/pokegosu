import { exactTokens } from '@/lib/format'
import { ko, type Box } from '@/lib/game'

import type { Outcome } from './use-game'

function nameOf(box: Box | null, speciesId: unknown): string {
  const found = box?.started ? box.pokemon.find((p) => p.species_id === speciesId) : undefined
  return found ? ko(found) : '포켓몬'
}

/** One line for what the last button did, in the games' voice where they have one. */
export function say(box: Box | null, fn: string, o: Outcome): string | null {
  switch (`${fn}:${o.outcome}`) {
    case 'claim:claimed':
      // A level gained is said apart, by levelUp, once the bar reaches it.
      return o.level_before === null
        ? `알이 토큰 ${exactTokens(Number(o.tokens))} 만큼 자랐다.`
        : `토큰 ${exactTokens(Number(o.tokens))} 을 얻었다!`
    case 'hatch:hatched':
      return `${o.is_shiny ? '✨ ' : ''}알에서 ${nameOf(box, o.species_id)}이(가) 태어났다!`
    case 'evolve:evolved':
      return `축하합니다! ${nameOf(box, o.to)}(으)로 진화했다!`
    case 'receive_egg:received':
      return '알을 받았다! 알 박스에 들어갔다.'
    case 'receive_ribbon:received':
      return '리본을 받았다!'
    case 'use_item:evolved':
      return `축하합니다! ${nameOf(box, o.to)}(으)로 진화했다!`
    case 'use_item:no_effect':
      return '써도 효과가 없을 것 같다.'
    case 'buy:bought':
      return o.companion_id ? '알을 샀다! 알 박스에 들어갔다.' : '샀다! 가방에 넣었다.'
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
  const found = box?.started ? box.pokemon.find((p) => p.id === companionId) : undefined
  const level = Number(o.level_after)
  return { level, line: `${found ? ko(found) : '포켓몬'}의 레벨이 ${level}(으)로 올랐다!` }
}
