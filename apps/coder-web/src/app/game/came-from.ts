import type { Before } from '@pokegosu/ui/artwork'

import { eggSpriteUrl, spriteUrl } from '@/lib/game'

import type { Last } from './use-game'

/**
 * What the Pokémon `id` was a moment ago, when the last action evolved or
 * hatched it, for its artwork to change out of. The render it evolved from is
 * only in the box from before the action.
 */
export function cameFrom(last: Last | null, id: string): Before | undefined {
  if (!last || !('companion_id' in last.action) || last.action.companion_id !== id) return
  const { fn } = last.action
  const { outcome } = last.outcome
  if (fn === 'hatch' && outcome === 'hatched') return { src: eggSpriteUrl, egg: true }
  if ((fn === 'evolve' || fn === 'use_item') && outcome === 'evolved') {
    const was = last.before?.started ? last.before.pokemon.find((p) => p.id === id) : undefined
    const src = was && spriteUrl(was, 'large')
    return src ? { src } : undefined
  }
}
