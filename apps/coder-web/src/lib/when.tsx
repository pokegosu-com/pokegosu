import { when } from './format'

/**
 * A time, in the reader's own zone.
 *
 * The server has no idea what that is, so it renders its own and the browser
 * replaces it. suppressHydrationWarning says that is intended, rather than
 * the mismatch React would otherwise report. The machine-readable instant
 * rides along in dateTime, where it is the same for everyone.
 */
export function When({ at }: { at: string | null }) {
  if (!at) return <>—</>

  return (
    <time dateTime={at} suppressHydrationWarning>
      {when(at)}
    </time>
  )
}
