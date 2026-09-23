const compact = new Intl.NumberFormat('ko-KR', { notation: 'compact', maximumFractionDigits: 1 })
const exact = new Intl.NumberFormat('ko-KR')

/** 480,910,116 → "4.8억": how big, at a glance. */
export function compactTokens(n: number | bigint): string {
  return compact.format(n)
}

/** 480,910,116 → "480,910,116": the number itself. */
export function exactTokens(n: number | bigint | string): string {
  return exact.format(typeof n === 'string' ? BigInt(n) : n)
}

/**
 * When something last happened, in the reader's own clock.
 *
 * Which is not the server's, so the server renders one string and the browser
 * another. <When> is how that is rendered; calling this directly in markup
 * gives React a hydration mismatch.
 */
export function when(at: string | null): string {
  if (!at) return '—'
  return new Date(at).toLocaleString('ko-KR', { dateStyle: 'medium', timeStyle: 'short' })
}
