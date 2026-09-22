// redeem-enrollment-code — a machine trades a code for a credential.
//
//   POST /functions/v1/redeem-enrollment-code
//
//   { "code": "XPTQ-4F2K",
//     "device_id": "<uuid the machine made up>",
//     "device_name": "laptop" }
//
//   → 201 { "api_key": "pkt_...", "device_id": "...", "device_name": "laptop" }
//
// Nothing authenticates this call, because the code IS the credential and a
// machine has nothing else yet. That is the whole reason the code is short
// lived, single use, and one per account.
//
// A machine the same account already registered is enrolled again with the
// new key, which is how a retired machine, or one that lost its settings but
// kept its id, comes back.
//
// The plaintext key is returned once. Only its sha256 is kept, so a leak of
// the database cannot be turned back into working keys.

import { normalize } from '../_shared/code.ts'
import { call } from '../_shared/db.ts'
import { digestOf } from '../_shared/digest.ts'
import { fail, HttpError, json, readJson, requirePost } from '../_shared/http.ts'
import { nonEmptyString, uuid } from '../_shared/validate.ts'

const MAX_NAME_LENGTH = 100

/** The prefix makes a leaked key recognisable in logs and to secret scanners;
 * the 32 random bytes are what make it a credential. */
const KEY_PREFIX = 'pkt_'

function mintKey(): string {
  const bytes = new Uint8Array(32)
  crypto.getRandomValues(bytes)
  return KEY_PREFIX + Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req: Request): Promise<Response> => {
  const wrongMethod = requirePost(req)
  if (wrongMethod !== null) return wrongMethod

  let code: string
  let deviceId: string
  let deviceName: string
  try {
    const body = await readJson(req)
    // normalize, not validate: someone who typed it in lower case or left the
    // dash in still gets in, and a wrong code simply matches nothing.
    code = normalize(nonEmptyString(body.code, 'code', 64))
    deviceId = uuid(body.device_id, 'device_id')
    deviceName = nonEmptyString(body.device_name, 'device_name', MAX_NAME_LENGTH)
  } catch (err) {
    if (err instanceof HttpError) return err.toResponse()
    throw err
  }

  const apiKey = mintKey()
  let result
  try {
    result = await call('redeem_enrollment_code', {
      code_hash: await digestOf(code),
      device_id: deviceId,
      device_name: deviceName,
      api_key_hash: await digestOf(apiKey),
    })
  } catch (err) {
    console.error(err)
    return fail(500, 'internal_error', 'could not redeem that code')
  }

  switch (result.outcome) {
    case 'redeemed':
      // The only time the plaintext exists anywhere but in the caller's hands.
      return json({ api_key: apiKey, device_id: deviceId, device_name: deviceName }, 201)

    // Expired, spent and never issued are one answer. Telling them apart
    // would only help someone guessing.
    case 'code_invalid':
      return fail(
        401,
        'enrollment_code_invalid',
        'that code is not valid: ask the web for a new one',
      )

    // The code is not spent, so the person can use it on the right machine.
    case 'device_taken':
      return fail(
        409,
        'device_owned_by_another_account',
        'that machine is already registered to another account',
      )

    default:
      console.error('redeem_enrollment_code answered', result)
      return fail(500, 'internal_error', 'could not redeem that code')
  }
})
