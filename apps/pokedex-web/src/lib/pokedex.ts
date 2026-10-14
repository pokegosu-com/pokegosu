import { createClient } from '@pokegosu/supabase/server'

/** Anything named in Korean and English, either of which may be missing. */
export type Named = { ko_name: string | null; en_name: string | null }

/** This app is in Korean; English stands in for a name missing in it. */
export function ko(named: Named): string {
  return named.ko_name ?? named.en_name ?? ''
}

/** The pokedexes, in the order the top bar shows them: national first, then by generation. */
export const DEXES = [
  'national',
  'kanto',
  'johto',
  'hoenn',
  'sinnoh',
  'unova',
  'kalos',
  'alola',
  'galar',
  'hisui',
  'paldea',
  'lumiose',
]

export function dexNo(n: number): string {
  return `No.${String(n).padStart(3, '0')}`
}

/**
 * A build reads the database some twenty thousand times, and one answer of
 * a server's error failed a whole deploy; supabase-js asks again only after
 * a 503 or 520. A read changes nothing, so it is asked again after any 5xx,
 * a 429 or a dropped connection, waiting longer each time.
 */
async function patientFetch(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  const method = (init?.method ?? 'GET').toUpperCase()
  const tries = method === 'GET' || method === 'HEAD' ? 5 : 1
  for (let attempt = 1; ; attempt++) {
    try {
      const response = await fetch(input, init)
      const transient = response.status >= 500 || response.status === 429
      if (!transient || attempt === tries) return response
      await response.body?.cancel()
    } catch (error) {
      if (init?.signal?.aborted || attempt === tries) throw error
    }
    await new Promise((resolve) => setTimeout(resolve, 1000 * 2 ** attempt))
  }
}

/**
 * The pokedex_ tables are readable by anyone, so these pages read them as a
 * visitor: no session, and no cookies to keep.
 */
export function pokedex() {
  return createClient({ getAll: () => [], setAll: () => {} }, patientFetch)
}

/**
 * PostgREST gives at most a thousand rows a request, and cuts the rest off
 * without saying so; the national pokedex outgrows that. The query is asked
 * a page at a time, so it needs an order.
 */
export async function every<T>(
  page: (from: number, to: number) => PromiseLike<{ data: T[] | null; error: Error | null }>,
): Promise<T[]> {
  const size = 1000
  const rows: T[] = []
  for (let from = 0; ; from += size) {
    const { data, error } = await page(from, from + size - 1)
    if (error) throw error
    rows.push(...data!)
    if (data!.length < size) return rows
  }
}

export async function typeNames(): Promise<Map<string, string>> {
  const { data, error } = await pokedex().from('pokedex_types').select('id, ko_name, en_name')
  if (error) throw error
  return new Map(data.map((t) => [t.id, ko(t)]))
}
