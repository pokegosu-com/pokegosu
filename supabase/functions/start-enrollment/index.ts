// start-enrollment — a machine asks to be let in.
//
//   POST /functions/v1/start-enrollment
//
//   { "code": "XPTQ4F2K",
//     "device_id": "<uuid the machine made up>",
//     "device_name": "laptop" }
//
//   → 201 { "claim_token": "pge_...", "expires_at": "..." }
//
// Nothing authenticates this call: the machine has nothing yet, and what it
// leaves behind is worth nothing on its own. A person has to read the code
// off that machine's own terminal and approve it before anything is handed
// out, and the key is handed to whoever holds the claim token, which is the
// server's own and goes only to the machine that asked.
//
// The code is the machine's, drawn locally. Only its digest is stored, of the
// normalised form, so that what a person types in the web matches whatever
// the machine drew.

import { normalize } from '../_shared/code.ts'
import { call } from '../_shared/db.ts'
import { digestOf } from '../_shared/digest.ts'
import { fail, HttpError, json, readJson, requirePost } from '../_shared/http.ts'
import { nonEmptyString, uuid } from '../_shared/validate.ts'

const MAX_NAME_LENGTH = 100

/** How long a request is good for. Long enough to find the web and sign in,
 * short enough that a machine left waiting stops waiting. */
const LIFETIME = '10 minutes'

/** The prefix makes a leaked token recognisable in logs and to secret
 * scanners; the 32 random bytes are what make it a credential. */
function mintClaimToken(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  return 'pge_' + Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req: Request): Promise<Response> => {
  const wrongMethod = requirePost(req)
  if (wrongMethod !== null) return wrongMethod

  let code: string
  let deviceId: string
  let deviceName: string
  try {
    const body = await readJson(req)
    code = normalize(nonEmptyString(body.code, 'code', 64))
    deviceId = uuid(body.device_id, 'device_id')
    deviceName = nonEmptyString(body.device_name, 'device_name', MAX_NAME_LENGTH)
  } catch (err) {
    if (err instanceof HttpError) return err.toResponse()
    throw err
  }

  const claimToken = mintClaimToken()
  let result
  try {
    result = await call('start_enrollment', {
      code_hash: await digestOf(code),
      claim_hash: await digestOf(claimToken),
      device_id: deviceId,
      device_name: deviceName,
      lifetime: LIFETIME,
    })
  } catch (err) {
    console.error(err)
    return fail(500, 'internal_error', 'could not start enrolling this machine')
  }

  switch (result.outcome) {
    case 'started':
      // The only time the claim token exists anywhere but in the caller's hands.
      return json({ claim_token: claimToken, expires_at: result.expires_at }, 201)

    // Someone else is waiting on that code. Saying so is safe — it is not a
    // credential — and lets the machine draw another and try again.
    case 'code_taken':
      return fail(409, 'enrollment_code_taken', 'that code is in use; draw another')

    default:
      console.error('start_enrollment answered', result)
      return fail(500, 'internal_error', 'could not start enrolling this machine')
  }
})
