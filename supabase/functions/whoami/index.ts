// whoami — a machine asks which machine it is, and whose.
//
//   POST /functions/v1/whoami
//   x-api-key: pgt_...
//
//   → 200 { "device_id": "...", "device_name": "laptop",
//           "display_name": "Ash" }
//
// What `pokegosu auth status` shows. The settings on the machine say what it
// was enrolled as; asking here also says whether its key still works, and
// what the account is called now rather than when the machine was let in.
// display_name is null for an account that has not picked a handle yet.

import { call } from '../_shared/db.ts'
import { digestOf } from '../_shared/digest.ts'
import { fail, json, requirePost } from '../_shared/http.ts'

Deno.serve(async (req: Request): Promise<Response> => {
  const wrongMethod = requirePost(req)
  if (wrongMethod !== null) return wrongMethod

  const key = req.headers.get('x-api-key')
  if (key === null || key === '') {
    return fail(401, 'unauthorized', 'x-api-key header is required')
  }

  let result
  try {
    result = await call('whoami', { api_key_hash: await digestOf(key) })
  } catch (err) {
    console.error(err)
    return fail(500, 'internal_error', 'could not look up this machine')
  }

  switch (result.outcome) {
    case 'found':
      return json({
        device_id: result.device_id,
        device_name: result.device_name,
        display_name: result.display_name,
      })

    // A revoked key is treated exactly like an unknown one: the caller learns
    // that the key does not work, not why.
    case 'unauthorized':
      return fail(401, 'unauthorized', 'unknown or revoked API key')

    default:
      console.error('whoami answered', result)
      return fail(500, 'internal_error', 'could not look up this machine')
  }
})
