import { createClient } from '@pokegosu/supabase/server'

/** Anything named in Korean and English, either of which may be missing. */
export type Named = { ko_name: string | null; en_name: string | null }

/** This app is in Korean; English stands in for a name missing in it. */
export function ko(named: Named): string {
  return named.ko_name ?? named.en_name ?? ''
}

export function dexNo(n: number): string {
  return `No.${String(n).padStart(3, '0')}`
}

/**
 * species and the pokedex are readable by anyone, so these pages read them as
 * a visitor: no session, and no cookies to keep.
 */
export function pokedex() {
  return createClient({ getAll: () => [], setAll: () => {} })
}

export async function typeNames(): Promise<Map<string, string>> {
  const { data, error } = await pokedex().from('types').select('id, ko_name, en_name')
  if (error) throw error
  return new Map(data.map((t) => [t.id, ko(t)]))
}
