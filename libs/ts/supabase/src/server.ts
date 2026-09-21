import { createServerClient, type CookieOptions } from '@supabase/ssr'

import type { Database } from './database.types'
import { supabaseEnv as env } from './env'

// Re-exported so apps can name Supabase's types without depending on
// @supabase/supabase-js directly, which pnpm would reject as a phantom.
export type { EmailOtpType } from '@supabase/supabase-js'

export type CookieToSet = { name: string; value: string; options: CookieOptions }

/**
 * How to read and write cookies, supplied by the caller. Next reaches cookies
 * differently depending on where the code runs — a page may only read them, a
 * route handler may write, and proxy.ts reads the request and writes the
 * response — so the client cannot hardcode one way.
 */
export type CookieStore = {
  getAll: () => { name: string; value: string }[] | Promise<{ name: string; value: string }[]>
  setAll: (cookies: CookieToSet[]) => void | Promise<void>
}

export type ServerClient = ReturnType<typeof createServerClient<Database>>

/** Return type is written out: pnpm's isolated node_modules leaves the inferred
 *  Supabase types unnameable from a consuming package. */
export function createClient(cookies: CookieStore): ServerClient {
  return createServerClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    {
      cookies,
      cookieOptions: env.NEXT_PUBLIC_COOKIE_DOMAIN
        ? { domain: env.NEXT_PUBLIC_COOKIE_DOMAIN }
        : undefined,
    },
  )
}
