/** Connection settings, validated eagerly so a missing value fails at startup. */
export type SupabaseEnv = {
  url: string
  publishableKey: string
  /**
   * Shared cookie domain, e.g. `.example.com`, so a session established on
   * account.example.com is visible on example.com. Unset locally: both apps
   * are on localhost and cookies ignore the port.
   */
  cookieDomain?: string
}

function required(name: string, value: string | undefined): string {
  if (!value) {
    throw new Error(
      `Missing environment variable ${name}. Copy .env.example to .env.local; ` +
        '`moon run supabase:status` prints the local values.',
    )
  }
  return value
}

/**
 * `process.env.NEXT_PUBLIC_*` is spelled out literally because Next inlines
 * those at build time by matching that exact expression — read through a
 * variable they would be undefined in the browser bundle.
 *
 * Callers outside Next pass `overrides` instead.
 */
export function readSupabaseEnv(overrides: Partial<SupabaseEnv> = {}): SupabaseEnv {
  return {
    url:
      overrides.url ?? required('NEXT_PUBLIC_SUPABASE_URL', process.env.NEXT_PUBLIC_SUPABASE_URL),
    publishableKey:
      overrides.publishableKey ??
      required(
        'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
        process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
      ),
    cookieDomain: overrides.cookieDomain ?? process.env.NEXT_PUBLIC_COOKIE_DOMAIN,
  }
}
