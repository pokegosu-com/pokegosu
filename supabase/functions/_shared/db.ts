// Database access for Edge Functions.
//
// These functions serve machines, which are not signed-in people, so they
// connect with the secret key. They reach the database only through the
// functions granted to service_role — start_enrollment, claim_enrollment,
// ingest and retire_device — and never through a table. The secret key would
// let them do far more; keeping every call to one of those is what keeps a
// mistake here small.

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2'

let client: SupabaseClient | null = null

/**
 * secretKey is the credential this code connects with.
 *
 * It is read from two places because the two environments name it
 * differently. A deployed function is given SUPABASE_SECRET_KEYS, a JSON
 * object of named keys; the local stack does not set that and supplies the
 * older SUPABASE_SERVICE_ROLE_KEY instead. Reading both is what lets the same
 * code run in both places.
 *
 * A malformed SUPABASE_SECRET_KEYS throws rather than falling through to the
 * legacy key. Falling through would start a deployment on a credential that
 * is about to stop existing, and say nothing about it.
 */
export function secretKey(env: (name: string) => string | undefined): string {
  const named = env('SUPABASE_SECRET_KEYS')
  if (named !== undefined && named !== '') {
    let keys: unknown
    try {
      keys = JSON.parse(named)
    } catch {
      throw new Error('SUPABASE_SECRET_KEYS is not valid JSON')
    }
    const key = (keys as Record<string, unknown>)?.default
    if (typeof key !== 'string' || key === '') {
      throw new Error('SUPABASE_SECRET_KEYS has no "default" key')
    }
    return key
  }

  const legacy = env('SUPABASE_SERVICE_ROLE_KEY')
  if (legacy !== undefined && legacy !== '') return legacy

  throw new Error('no secret key: expected SUPABASE_SECRET_KEYS or SUPABASE_SERVICE_ROLE_KEY')
}

function admin(): SupabaseClient {
  if (client === null) {
    client = createClient(
      Deno.env.get('SUPABASE_URL')!,
      secretKey((name) => Deno.env.get(name)),
      { auth: { persistSession: false, autoRefreshToken: false } },
    )
  }
  return client
}

/** Outcome is what the two functions answer with when nothing went wrong
 * in the database: `{"outcome": "..."}` and whatever goes with it. */
export type Outcome = { outcome: string } & Record<string, unknown>

/**
 * call runs one of the functions granted to service_role and returns its
 * outcome. A database error is thrown: it is never an answer a caller should
 * see, only something to log and turn into a 500.
 */
export async function call(
  fn: 'start_enrollment' | 'claim_enrollment' | 'ingest' | 'retire_device',
  args: Record<string, unknown>,
): Promise<Outcome> {
  const { data, error } = await admin().rpc(fn, args)
  if (error !== null) {
    throw new Error(`${fn} failed: ${error.code} ${error.message}`)
  }
  return data as Outcome
}
