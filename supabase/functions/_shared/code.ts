// What a person typed, turned back into the code they were given.
//
// The code is drawn by create_enrollment_code, in SQL, from an alphabet with
// no I, L, O or U. It is read off one screen and typed into another, so input
// is normalised rather than validated: someone who types it in lower case,
// forgets the dash, or pastes it with a space still gets in.

/**
 * normalize turns what a person typed into what was issued, or into
 * something that will simply not be found.
 *
 * Dropping I, L and O from the alphabet is only half of that decision; the
 * other half is here. Nobody who reads a 1 as an I should be told their code
 * is wrong, so those characters are folded back to the digits they were
 * mistaken for. Anything else — spaces, the dash, a stray quote — is dropped.
 *
 * It does not judge the input. A wrong length or a leftover character makes a
 * string no digest matches, and "no such code" is the honest answer to both a
 * typo and a guess. Telling those apart would only help the guesser.
 */
export function normalize(typed: string): string {
  return typed
    .toUpperCase()
    .replace(/[IL]/g, '1')
    .replace(/O/g, '0')
    .replace(/[^0-9A-Z]/g, '')
}
