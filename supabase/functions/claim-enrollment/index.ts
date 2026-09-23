// claim-enrollment — a machine collects the key it was approved for.
//
//   POST /functions/v1/claim-enrollment
//
//   { "claim_token": "pge_..." }
//
//   → 200 { "api_key": "pgt_...", "device_name": "laptop",
//           "enrolled_at": "..." }                             approved
//   → 202 { "status": "waiting" }                             not yet
//
// The key is minted here, on the call that hands it over, so it exists only
// for the machine that asked and never passes through the browser that
// approved it. Only its sha256 is kept, so a leak of the database cannot be
// turned back into working keys.
//
// The claim token is what authenticates this: the server made it and gave it
// to one machine, at the start of its own enrolment.

import { call } from '../_shared/db.ts'
import { digestOf } from '../_shared/digest.ts'
import { fail, HttpError, json, readJson, requirePost } from '../_shared/http.ts'
import { nonEmptyString } from '../_shared/validate.ts'

/** The prefix makes a leaked key recognisable in logs and to secret scanners;
 * the 32 random bytes are what make it a credential. */
function mintKey(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  return 'pgt_' + Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req: Request): Promise<Response> => {
  const wrongMethod = requirePost(req)
  if (wrongMethod !== null) return wrongMethod

  let claimToken: string
  try {
    const body = await readJson(req)
    claimToken = nonEmptyString(body.claim_token, 'claim_token', 128)
  } catch (err) {
    if (err instanceof HttpError) return err.toResponse()
    throw err
  }

  const apiKey = mintKey()
  let result
  try {
    result = await call('claim_enrollment', {
      claim_hash: await digestOf(claimToken),
      api_key_hash: await digestOf(apiKey),
    })
  } catch (err) {
    console.error(err)
    return fail(500, 'internal_error', 'could not finish enrolling this machine')
  }

  switch (result.outcome) {
    case 'registered':
      // The only time the plaintext exists anywhere but in the caller's hands.
      return json({
        api_key: apiKey,
        device_name: result.device_name,
        // When this machine was first let in. A service reads it to know how
        // far back the logs it finds are this machine's to report.
        enrolled_at: result.enrolled_at,
      })

    // Nobody has approved it yet. Not an error: the machine is meant to ask
    // again, which is why this is a status rather than a failure.
    case 'waiting':
      return json({ status: 'waiting' }, 202)

    // Expired, already collected, or a token nobody was given: one answer.
    case 'not_found':
      return fail(
        404,
        'enrollment_not_found',
        'this request is no longer waiting; run pokegosu auth login again',
      )

    case 'device_taken':
      return fail(409, 'device_owned_by_another_account', 'that machine id is already registered')

    default:
      console.error('claim_enrollment answered', result)
      return fail(500, 'internal_error', 'could not finish enrolling this machine')
  }
})
