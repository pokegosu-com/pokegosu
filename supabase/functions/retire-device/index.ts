// retire-device — a machine retires itself, for `pokegosu auth logout`.
//
//   POST /functions/v1/retire-device
//   x-api-key: pgt_...
//
//   → 200 { "device_name": "laptop" }
//
// It is the retirement the web does, asked for with the machine's own key, so
// a machine being handed on or wiped does not need someone to find it in the
// web first. The key stops working, and the machine keeps the history it
// earned. There is no body: which machine this is comes from the key.

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
    result = await call('retire_device', { api_key_hash: await digestOf(key) })
  } catch (err) {
    console.error(err)
    return fail(500, 'internal_error', 'could not retire this machine')
  }

  switch (result.outcome) {
    case 'retired':
      return json({ device_name: result.device_name })

    // Already retired reads the same as never known, as it does for ingest.
    case 'unauthorized':
      return fail(401, 'unauthorized', 'unknown or revoked API key')

    default:
      console.error('retire_device answered', result)
      return fail(500, 'internal_error', 'could not retire this machine')
  }
})
