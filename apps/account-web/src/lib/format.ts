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
