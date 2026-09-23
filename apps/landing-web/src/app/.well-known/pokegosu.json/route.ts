import { env } from '@/env'

/**
 * What `pokegosu auth login` reads to find a deployment's parts.
 *
 * It lives at the root, on the address people know, because it describes the
 * deployment rather than any one app: where the API is, and where a person
 * signs in and approves a machine. Both can move without a CLI release.
 *
 * Inlined at build time like the rest of this app, so it is a static file.
 */
export function GET() {
  return Response.json({
    api_url: env.NEXT_PUBLIC_SUPABASE_URL,
    account_url: env.NEXT_PUBLIC_ACCOUNT_URL,
  })
}
