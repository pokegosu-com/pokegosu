import { createBrowserClient } from '@supabase/ssr'

import type { Database } from './database.types'
import { supabaseEnv as env } from './env'

/** Client for browser code. createBrowserClient memoises, so per-render is fine. */
export function createClient() {
  return createBrowserClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookieOptions: env.NEXT_PUBLIC_COOKIE_DOMAIN
        ? { domain: env.NEXT_PUBLIC_COOKIE_DOMAIN }
        : undefined,
    },
  )
}

export type BrowserClient = ReturnType<typeof createClient>
