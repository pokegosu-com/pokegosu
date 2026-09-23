import { createEnv } from '@t3-oss/env-nextjs'
import * as z from 'zod'

/**
 * Validated when this module loads. vite.config.ts imports it, so a missing or
 * malformed value fails the build rather than a sign-in redirect.
 */
export const env = createEnv({
  client: {
    /** Where people sign in; this app sends them there without a session. */
    NEXT_PUBLIC_ACCOUNT_URL: z.url(),
  },
  experimental__runtimeEnv: {
    NEXT_PUBLIC_ACCOUNT_URL: process.env.NEXT_PUBLIC_ACCOUNT_URL,
  },
  emptyStringAsUndefined: true,
  // For builds that only check the code, such as `moon ci`. A deploy must
  // never set it.
  skipValidation: !!process.env.SKIP_ENV_VALIDATION,
})
