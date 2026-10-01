/**
 * The final consonant a word ends on when read aloud, as its index among
 * Hangul's 28 finals (0 for none, 8 for ㄹ), or null where it can't be told.
 * A number is read the Sino-Korean way: 60 is 육십, 2 is 이. A sign at the
 * end is not read: 니드런♀ is read as 니드런.
 */
function finalOf(name: string): number | null {
  const word = name.replace(/[^\p{L}\p{N}]+$/u, '')
  const zeros = /[1-9]0+$/.test(word)
  if (zeros) return 1 // 십, 백, 천, 만
  const digit = /\d$/.test(word) ? Number(word.at(-1)) : null
  if (digit !== null) return [21, 8, 0, 16, 0, 0, 1, 8, 8, 0][digit]
  const code = (word.at(-1) ?? '').charCodeAt(0) - 0xac00
  return code >= 0 && code < 11172 ? code % 28 : null
}

/** A word with the particle its last sound takes, or both where that can't be told. */
export function josa(word: string, after: '이' | '을' | '으로'): string {
  const final = finalOf(word)
  if (after === '으로') {
    if (final === null) return `${word}(으)로`
    return `${word}${final === 0 || final === 8 ? '로' : '으로'}`
  }
  const without = after === '이' ? '가' : '를'
  if (final === null) return `${word}${after}(${without})`
  return `${word}${final === 0 ? without : after}`
}
