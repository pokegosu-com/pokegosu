// ingest — record what a machine has used.
//
// The body is a set of absolute hourly totals, not increments: "the 14:00
// bucket is 3,200,000 tokens". Sending the same bucket again is therefore
// harmless, and a client that recomputes recent hours on every sync converges
// on the truth without the server reasoning about what it has already seen.
//
//   POST /functions/v1/ingest
//   x-api-key: pgt_...
//
//   { "rollups": [ { "provider": "claude_code",
//                    "hour_bucket": "2026-09-12T14:00:00Z",
//                    "tokens": 3200000 } ] }
//
//   → 200 { "accepted": 1, "ignored": 0 }
//
// Everything about the body is checked here, before the database is asked
// anything, so that a malformed request costs no query and a wrong row is
// named. Which machine this is comes from the key, never from the body.
//
// Hours from before the machine was enrolled are ignored rather than refused,
// and counted back so a client can say so if it wants to.

import { call } from '../_shared/db.ts'
import { digestOf } from '../_shared/digest.ts'
import { fail, HttpError, invalid, json, readJson, requirePost } from '../_shared/http.ts'
import { array, hourBucket, tokenCount } from '../_shared/validate.ts'

// A routine sync carries one or two rows. The cap is for a first run
// backfilling months of logs; past it a client sends batches, which costs
// nothing because the rows are absolute values.
const MAX_ROLLUPS = 10_000

type Rollup = { provider: string; hour_bucket: string; tokens: number }

Deno.serve(async (req: Request): Promise<Response> => {
  const wrongMethod = requirePost(req)
  if (wrongMethod !== null) return wrongMethod

  const key = req.headers.get('x-api-key')
  if (key === null || key === '') {
    return fail(401, 'unauthorized', 'x-api-key header is required')
  }

  let rollups: Rollup[]
  try {
    const body = await readJson(req)
    rollups = parseRollups(body.rollups)
  } catch (err) {
    if (err instanceof HttpError) return err.toResponse()
    throw err
  }

  let result
  try {
    result = await call('ingest', { api_key_hash: await digestOf(key), rollups })
  } catch (err) {
    console.error(err)
    return fail(500, 'internal_error', 'could not record the rollups')
  }

  switch (result.outcome) {
    case 'accepted':
      return json({ accepted: result.accepted, ignored: result.ignored })

    // A revoked key is treated exactly like an unknown one: the caller learns
    // that the key does not work, not why.
    case 'unauthorized':
      return fail(401, 'unauthorized', 'unknown or revoked API key')

    case 'unknown_provider':
      return fail(
        400,
        'invalid_request',
        `unknown provider "${result.provider}"; known providers are ${(result.known as string[]).join(', ')}`,
      )

    default:
      console.error('ingest answered', result)
      return fail(500, 'internal_error', 'could not record the rollups')
  }
})

function parseRollups(value: unknown): Rollup[] {
  const entries = array(value, 'rollups', MAX_ROLLUPS)
  const seen = new Set<string>()

  return entries.map((entry, i) => {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      throw invalid(`rollups[${i}] must be an object`)
    }
    const row = entry as Record<string, unknown>
    const rollup: Rollup = {
      provider: providerId(row.provider, `rollups[${i}].provider`),
      hour_bucket: hourBucket(row.hour_bucket, `rollups[${i}].hour_bucket`),
      tokens: tokenCount(row.tokens, `rollups[${i}].tokens`),
    }

    // One request cannot carry the same bucket twice: the upsert would have
    // to pick a winner, and the client already knows which value it means.
    const key = JSON.stringify([rollup.provider, rollup.hour_bucket])
    if (seen.has(key)) {
      throw invalid(
        `rollups[${i}] repeats ${rollup.provider} at ${rollup.hour_bucket}; send one row per bucket`,
      )
    }
    seen.add(key)

    return rollup
  })
}

function providerId(value: unknown, field: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw invalid(`${field} must be a provider id`)
  }
  return value.trim()
}
