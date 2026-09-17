import { createBrowserClient } from '@supabase/ssr'

import type { Database } from './database.types'
import { readSupabaseEnv, type SupabaseEnv } from './env'

/** Client for browser code. createBrowserClient memoises, so per-render is fine. */
export function createClient(overrides: Partial<SupabaseEnv> = {}) {
  const env = readSupabaseEnv(overrides)

  return createBrowserClient<Database>(env.url, env.publishableKey, {
    cookieOptions: env.cookieDomain ? { domain: env.cookieDomain } : undefined,
  })
}

export type BrowserClient = ReturnType<typeof createClient>
