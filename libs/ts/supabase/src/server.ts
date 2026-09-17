import { createServerClient, type CookieOptions } from '@supabase/ssr'

import type { Database } from './database.types'
import { readSupabaseEnv, type SupabaseEnv } from './env'

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
export function createClient(
  cookies: CookieStore,
  overrides: Partial<SupabaseEnv> = {},
): ServerClient {
  const env = readSupabaseEnv(overrides)

  return createServerClient<Database>(env.url, env.publishableKey, {
    cookies,
    cookieOptions: env.cookieDomain ? { domain: env.cookieDomain } : undefined,
  })
}
