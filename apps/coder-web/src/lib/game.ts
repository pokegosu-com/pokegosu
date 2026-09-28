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
  /** Tokens it has taken, and needs to hatch. */
  tokens: number
  tokens_needed: number
  is_main: boolean
  markings: number
}

/** Anything named in Korean and English, either of which may be missing. */
export type Named = { ko_name: string | null; en_name: string | null }

export type Pokemon = {
  id: string
  species_id: number
  dex_no: number
  ko_name: string | null
  en_name: string | null
  sprites: Sprites
  growth_rate: string
  types: ({ id: string } & Named)[]
  is_shiny: boolean
  /** Null for a genderless species. */
  gender: 'female' | 'male' | null
  level: number
  /** Its experience in tokens, at today's rate, and where its level starts and ends. */
  tokens: number
  level_tokens: number
  next_level_tokens: number | null
  /** What Lv.100 takes; experience past it has nowhere to go. */
  max_tokens: number
  evolves_to: ({ species_id: number; level: number } & Named) | null
  can_evolve: boolean
  can_receive_egg: boolean
  ribbons: ({ id: string; received_at: string } & Named)[]
  ribbons_waiting: ({ id: string } & Named)[]
  created_at: string
  hatched_at: string
  is_main: boolean
  markings: number
}

/** This app is in Korean; English stands in for a text missing in it. */
export function ko(named: Named): string {
  return named.ko_name ?? named.en_name ?? ''
}

/** The paths pokedex_species.sprites keeps, on pokedex-web. */
export type Sprites = {
  front?: string
  front_shiny?: string
  /** Only where a female looks different. */
  front_female?: string
  front_shiny_female?: string
  artwork?: string
  artwork_shiny?: string
}

/**
 * The pixel front sprite for a list, the official artwork for a Pokémon on its
 * own. species keeps the paths; pokedex-web serves them.
 */
export function spriteUrl(
  pokemon: Pick<Pokemon, 'sprites' | 'is_shiny' | 'gender'>,
  size: 'small' | 'large',
): string | undefined {
  const { sprites, is_shiny } = pokemon
  const female = pokemon.gender === 'female'
  const path =
    size === 'small'
      ? is_shiny
        ? (female && sprites.front_shiny_female) || sprites.front_shiny
        : (female && sprites.front_female) || sprites.front
      : is_shiny
        ? sprites.artwork_shiny
        : sprites.artwork
  return path && `${env.NEXT_PUBLIC_POKEDEX_URL}${path}`
}

export const eggSpriteUrl = `${env.NEXT_PUBLIC_POKEDEX_URL}/sprites/egg.png`

/**
 * What to claim into the main companion: the lesser of what is left and what
 * it can still take. claim() cuts any amount down to the same, so this only
 * keeps the button from offering what would come back as nothing.
 */
export function claimable(box: Box): number {
  if (!box.started) return 0
  const left = Number(BigInt(box.balance) > 0n ? BigInt(box.balance) : 0n)
  const pokemon = box.pokemon.find((p) => p.id === box.main_companion_id)
  const egg = box.eggs.find((e) => e.id === box.main_companion_id)
  const room = pokemon
    ? pokemon.max_tokens - pokemon.tokens
    : egg
      ? egg.tokens_needed - egg.tokens
      : 0
  return Math.max(0, Math.min(left, room))
}

/** The game's experience curve: per growth rate, the tokens each level starts at, Lv.1 first. */
export type Curve = Map<string, number[]>

/** The level a number of tokens reaches, and where that level starts and ends. */
export function levelAt(curve: Curve, growthRate: string, tokens: number) {
  const starts = curve.get(growthRate)
  if (!starts?.length) return null
  let level = 1
  while (level < starts.length && starts[level] <= tokens) level += 1
  return { level, from: starts[level - 1], to: level < starts.length ? starts[level] : null }
}

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
  const left = 1 - egg.tokens / egg.tokens_needed
  if (left <= 0) return '안에서 소리가 들린다! 곧 태어날 것 같다!'
  if (left <= 0.1) return '가끔 움직이고 있다. 태어나기까지 조금 더 걸릴 것 같다.'
  if (left <= 0.4) return '안에서 소리가 들리는 것 같다. 곧 태어날 것 같다.'
  return '무엇이 태어날까? 태어나려면 아직 시간이 많이 걸릴 것 같다.'
}
