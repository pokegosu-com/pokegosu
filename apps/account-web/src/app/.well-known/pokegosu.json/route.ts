import { supabaseEnv } from '@pokegosu/supabase/env'

/**
 * What `pokegosu login --url https://account.example.com` reads to find the
 * API. People only ever see this app's address; where the backend lives is
 * this document's business, and it can move without a CLI release.
 */
export function GET() {
  return Response.json({ api_url: supabaseEnv.NEXT_PUBLIC_SUPABASE_URL })
}
