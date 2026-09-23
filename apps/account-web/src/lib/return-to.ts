import { supabaseEnv } from '@pokegosu/supabase/env'

/**
 * Where to send someone after they sign in, when another app sent them here:
 * coder.example.com links to /login?next=https://coder.example.com/devices.
 *
 * Only an app that shares the session may be named — a host under the cookie
 * domain, or localhost where there is no cookie domain — so this cannot be
 * used to bounce a freshly signed-in person to somebody else's site.
 * Anything else is null, and the caller falls back to this app's own page.
 */
export function safeReturnTo(value: string | null | undefined): string | null {
  if (!value) return null

  let url: URL
  try {
    url = new URL(value)
  } catch {
    return null
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return null

  const domain = supabaseEnv.NEXT_PUBLIC_COOKIE_DOMAIN
  const allowed = domain
    ? url.hostname === domain.slice(1) || url.hostname.endsWith(domain)
    : url.hostname === 'localhost' || url.hostname === '127.0.0.1'

  return allowed ? url.toString() : null
}

/**
 * The cookie that carries it across the emailed link. The link's redirect
 * address must match the auth server's allow list exactly, so the
 * destination cannot ride along in it; it waits here instead, on this app's
 * own domain, for as long as a sign-in link is worth using.
 */
export const RETURN_TO_COOKIE = 'return_to'
export const RETURN_TO_MAX_AGE = 60 * 60
