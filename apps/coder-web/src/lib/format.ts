const compact = new Intl.NumberFormat('en-US', { notation: 'compact', maximumFractionDigits: 1 })
const exact = new Intl.NumberFormat('ko-KR')

/** 480,910,116 → "480.9M": how big, at a glance, in K, M, B and T rather than 만 and 억. */
export function compactTokens(n: number | bigint): string {
  return compact.format(n)
}

/** 480,910,116 → "480,910,116": the number itself. */
export function exactTokens(n: number | bigint | string): string {
  return exact.format(typeof n === 'string' ? BigInt(n) : n)
}

/** 12480 → "12,480 P". */
export function points(n: number): string {
  return `${exact.format(n)} P`
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
