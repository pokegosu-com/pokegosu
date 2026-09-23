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

/** A name or text in every language the pokedex keeps, keyed like "ko" or "zh-Hans". */
export type Names = Record<string, string>

export type Pokemon = {
  id: string
  pokedex_id: number
  dex_no: number
  names: Names
  sprites: { animated?: string; animated_shiny?: string }
  types: { id: string; names: Names }[]
  is_shiny: boolean
  level: number
  exp: number
  level_exp: number
  next_level_exp: number | null
  evolves_to: { pokedex_id: number; names: Names; level: number } | null
  can_evolve: boolean
  can_receive_egg: boolean
  ribbons: { id: string; names: Names; received_at: string }[]
  ribbons_waiting: { id: string; names: Names }[]
  created_at: string
  hatched_at: string
  is_main: boolean
  markings: number
}

/** This app is in Korean; English stands in for a text the pokedex lacks in it. */
export function ko(names: Names): string {
  return names.ko ?? names.en ?? ''
}

/** The pokedex keeps sprite paths; pokedex-web serves them. */
export function spriteUrl(pokemon: Pick<Pokemon, 'sprites' | 'is_shiny'>): string | undefined {
  const path = pokemon.is_shiny ? pokemon.sprites.animated_shiny : pokemon.sprites.animated
  return path && `${env.NEXT_PUBLIC_POKEDEX_URL}${path}`
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
