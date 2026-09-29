import { env } from '@/env'

/** What box() answers with. */
export type Box =
  | { started: false; balance: string }
  | {
      started: true
      main_companion_id: string
      balance: string
      /** Points to spend in the shop, and what has been bought and not used. */
      points: number
      bag: BagItem[]
      eggs: Egg[]
      pokemon: Pokemon[]
    }

/** An item, with its sprite's path on pokedex-web. */
export type Item = { id: string; sprite: string | null } & Named

export type BagItem = Item & { quantity: number }

/** An item's pixel sprite, served by pokedex-web. */
export function itemSpriteUrl(item: Pick<Item, 'sprite'>): string | undefined {
  return item.sprite ? `${env.NEXT_PUBLIC_POKEDEX_URL}${item.sprite}` : undefined
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
  /** The form's name in the Pokédex, or null for a species' default form. */
  form_slug: string | null
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
  /** What it becomes with which item: Eevee has three. */
  item_evolutions: ({ species_id: number; item: Item } & Named)[]
  /** The workplace it is working at, if any. */
  workplace_id: string | null
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
  artwork_female?: string
  artwork_shiny_female?: string
}

/**
 * The pixel front sprite for a list, the large render for a Pokémon on its
 * own, a female's own where she looks different. species keeps the paths;
 * pokedex-web serves them.
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
        ? (female && sprites.artwork_shiny_female) || sprites.artwork_shiny
        : (female && sprites.artwork_female) || sprites.artwork
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

/** The item evolutions the bag holds the item for. */
export function usableItems(p: Pokemon, bag: BagItem[]) {
  return p.item_evolutions.filter((e) => bag.some((b) => b.id === e.item.id && b.quantity > 0))
}

/** What work() answers with. */
export type Work =
  | { started: false }
  | {
      started: true
      points: number
      rules: {
        points_per_hour: number
        shift_hours: number
        min_work_level: number
        bonus_every_hours: number
        bonus_points: number
      }
      /** The person's own workplace: active hours since it opened, and how many are paid. */
      trainer: {
        /** Their display name, which a trainer with a handle always has. */
        name: string | null
        hours: number
        hours_paid: number
        points_waiting: number
        hours_to_bonus: number
      }
      workplaces: Workplace[]
      pokemon: Worker[]
    }

/** A request (의뢰): a Pokémon asking for help with a task of one of its types. */
export type Workplace = {
  id: string
  slot: number
  /** The Pokémon it is for, as the pokedex has it. */
  client: { species_id: number; sprites: Sprites } & Named
  /** What it asks help with: 터널 파기, 디버깅. */
  task: { id: string } & Named
  types: ({ id: string } & Named)[]
  /** Active hours since it opened, which a reroll waits on. */
  hours_open: number
  can_reroll: boolean
  worker: {
    companion_id: string
    /** Active hours of its shift so far, up to the shift's length. */
    hours: number
    aptitude: number
    /** What settling will pay. */
    points: number
    can_settle: boolean
  } | null
}

/** A Pokémon that may work, and what each workplace would pay it for a shift. */
export type Worker = Pick<
  Pokemon,
  | 'id'
  | 'species_id'
  | 'ko_name'
  | 'en_name'
  | 'sprites'
  | 'is_shiny'
  | 'gender'
  | 'level'
  | 'types'
> & {
  workplace_id: string | null
  offers: { workplace_id: string; aptitude: number; points: number }[]
}

/** How a Pokémon takes to a workplace, as the multiplier its types give. */
export function aptitudeLine(aptitude: number): string {
  if (aptitude >= 4) return '매우 적성에 맞는다'
  if (aptitude >= 2) return '적성에 맞는다'
  if (aptitude >= 1) return '보통이다'
  if (aptitude >= 0.5) return '적성에 맞지 않는다'
  if (aptitude > 0) return '매우 적성에 맞지 않는다'
  return '전혀 모르는 분야인 것 같다'
}
