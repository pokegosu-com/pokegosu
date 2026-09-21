import { createEnv } from '@t3-oss/env-nextjs'
import * as z from 'zod'

/**
 * Connection settings, validated when this module loads. Each app imports it
 * from vite.config.ts, so a missing or malformed value fails the build rather
 * than a request.
 *
 * `process.env.NEXT_PUBLIC_*` is spelled out literally because Next inlines
 * those at build time by matching that exact expression — read through a
 * variable they would be undefined in the browser bundle.
 */
export const supabaseEnv = createEnv({
  client: {
    NEXT_PUBLIC_SUPABASE_URL: z.url(),
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().startsWith('sb_publishable_'),
    /**
     * Shared cookie domain, e.g. `.example.com`, so a session established on
     * account.example.com is visible on example.com. Unset locally: both apps
     * are on localhost and cookies ignore the port.
     */
    NEXT_PUBLIC_COOKIE_DOMAIN: z.string().startsWith('.').optional(),
  },
  experimental__runtimeEnv: {
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    NEXT_PUBLIC_COOKIE_DOMAIN: process.env.NEXT_PUBLIC_COOKIE_DOMAIN,
  },
  emptyStringAsUndefined: true,
  // For builds that only check the code, such as `moon ci`. A deploy must
  // never set it.
  skipValidation: !!process.env.SKIP_ENV_VALIDATION,
})
