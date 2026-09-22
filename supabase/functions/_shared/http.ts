// HTTP shapes shared by every function, so that clients in several languages
// see one error format instead of whatever each handler improvised.

export type ErrorCode =
  | 'unauthorized'
  | 'invalid_request'
  | 'device_owned_by_another_account'
  | 'enrollment_code_invalid'
  | 'method_not_allowed'
  | 'internal_error'

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json' },
  })
}

/**
 * fail returns the one error shape: a stable code a client can branch on and
 * a message meant for a human reading a terminal.
 */
export function fail(status: number, code: ErrorCode, message: string): Response {
  return json({ error: { code, message } }, status)
}

/** HttpError lets validation report a failure from wherever it happens. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
  ) {
    super(message)
  }

  toResponse(): Response {
    return fail(this.status, this.code, this.message)
  }
}

export function invalid(message: string): HttpError {
  return new HttpError(400, 'invalid_request', message)
}

/** requirePost rejects anything but POST. Every function here is a command. */
export function requirePost(req: Request): Response | null {
  if (req.method !== 'POST') {
    return fail(405, 'method_not_allowed', 'use POST')
  }
  return null
}

/** readJson parses a request body, reporting malformed JSON as a 400. */
export async function readJson(req: Request): Promise<Record<string, unknown>> {
  let body: unknown
  try {
    body = await req.json()
  } catch {
    throw invalid('body is not valid JSON')
  }
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    throw invalid('body must be a JSON object')
  }
  return body as Record<string, unknown>
}
