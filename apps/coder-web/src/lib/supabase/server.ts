import { cookies } from 'next/headers'

import { createClient as createSupabaseClient, type ServerClient } from '@pokegosu/supabase/server'

/**
 * Supabase client bound to this request's cookies.
 *
 * Usable from pages and route handlers. Only route handlers, server actions and
 * proxy.ts may actually write cookies; from a page the write is swallowed,
 * which is safe because proxy.ts has already refreshed the session.
 */
export async function createClient(): Promise<ServerClient> {
  const cookieStore = await cookies()

  return createSupabaseClient({
    getAll: () => cookieStore.getAll(),
    setAll: (cookiesToSet) => {
      try {
        for (const { name, value, options } of cookiesToSet) {
          cookieStore.set(name, value, options)
        }
      } catch {
        // Called from a page — the cookie store is read-only there.
      }
    },
  })
}
