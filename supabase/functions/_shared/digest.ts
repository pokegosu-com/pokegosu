// Hashing credentials, and rendering the result for Postgres.
//
// Two things are stored as sha256 and never as themselves: a machine's API
// key and an enrollment code. Both are looked up by digest, so this is on the
// path of every authenticated request. create_enrollment_code hashes the code
// in SQL the same way: sha256 of its UTF-8 bytes.

export async function sha256(value: string): Promise<Uint8Array> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return new Uint8Array(digest)
}

/** toHex renders bytes the way Postgres wants a bytea literal over PostgREST. */
export function toHex(bytes: Uint8Array): string {
  return '\\x' + Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
}

/** digestOf is the two together, which is how every caller wants them. */
export async function digestOf(value: string): Promise<string> {
  return toHex(await sha256(value))
}
