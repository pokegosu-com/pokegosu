import { createClient } from '@pokegosu/supabase/server'

/** A name or text in every language the pokedex keeps, keyed like "ko" or "zh-Hans". */
export type Names = Record<string, string>

/** The languages the pokedex keeps, as a reader would name each. */
export const LANGUAGES: [key: string, label: string][] = [
  ['ko', '한국어'],
  ['en', 'English'],
  ['ja', '日本語'],
  ['zh-Hans', '简体中文'],
  ['zh-Hant', '繁體中文'],
  ['fr', 'Français'],
  ['de', 'Deutsch'],
  ['es', 'Español'],
  ['it', 'Italiano'],
]

/** This app is in Korean; English stands in for a text the pokedex lacks in it. */
export function ko(names: unknown): string {
  const n = (names ?? {}) as Names
  return n.ko ?? n.en ?? ''
}

export function dexNo(n: number): string {
  return `No.${String(n).padStart(3, '0')}`
}

/**
 * The pokedex is readable by anyone, so these pages read it as a visitor:
 * no session, and no cookies to keep.
 */
export function pokedex() {
  return createClient({ getAll: () => [], setAll: () => {} })
}

export async function typeNames(): Promise<Map<string, string>> {
  const { data, error } = await pokedex().from('pokedex_types').select('id, names')
  if (error) throw error
  return new Map(data.map((t) => [t.id, ko(t.names)]))
}
