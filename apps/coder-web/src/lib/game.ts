import { env } from '@/env'

/** What box() answers with. */
export type Box =
  | { started: false; balance: string }
  | {
      started: true
      main_companion_id: string
      balance: string
      eggs: Egg[]
      pokemon: Pokemon[]
    }

export type Egg = {
  id: string
  created_at: string
  steps: number
  steps_needed: number
  is_main: boolean
  markings: number
}

export type Pokemon = {
  id: string
  species_id: number
  name: string
  types: { id: string; name: string }[]
  is_shiny: boolean
  level: number
  exp: number
  level_exp: number
  next_level_exp: number | null
  evolves_to: { id: number; name: string; level: number } | null
  can_evolve: boolean
  can_receive_egg: boolean
  ribbons: { id: string; name: string; received_at: string }[]
  ribbons_waiting: { id: string; name: string }[]
  created_at: string
  hatched_at: string
  is_main: boolean
  markings: number
}

export function spriteUrl(speciesId: number, shiny: boolean): string {
  return `${env.NEXT_PUBLIC_POKEDEX_URL}/sprites/pokemon/${shiny ? 'shiny/' : ''}${speciesId}.gif`
}

export const eggSpriteUrl = `${env.NEXT_PUBLIC_POKEDEX_URL}/sprites/egg.png`

/** The games' box marks, in the order their bits run from the lowest up. */
export const MARKS = ['●', '▲', '■', '♥', '★', '◆'] as const

/** 0 off, 1 blue, 2 red. */
export type MarkColor = 0 | 1 | 2

export function markOf(markings: number, index: number): MarkColor {
  return ((markings >> (index * 2)) & 3) as MarkColor
}

/** The same markings with one mark turned to its next state: off, blue, red, off. */
export function cycleMark(markings: number, index: number): number {
  const next = ((markOf(markings, index) + 1) % 3) as MarkColor
  return (markings & ~(3 << (index * 2))) | (next << (index * 2))
}

/** The games' hint for how long an egg has left, by the share still to go. */
export function eggHint(egg: Egg): string {
  const left = 1 - egg.steps / egg.steps_needed
  if (left <= 0) return '안에서 소리가 들린다! 곧 태어날 것 같다!'
  if (left <= 0.1) return '가끔 움직이고 있다. 태어나기까지 조금 더 걸릴 것 같다.'
  if (left <= 0.4) return '안에서 소리가 들리는 것 같다. 곧 태어날 것 같다.'
  return '무엇이 태어날까? 태어나려면 아직 시간이 많이 걸릴 것 같다.'
}
