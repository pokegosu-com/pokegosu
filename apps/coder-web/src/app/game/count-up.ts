'use client'

import { useEffect, useRef, useState } from 'react'

/**
 * A number that climbs to its target rather than jumping there, so an egg is
 * watched filling up. It only ever climbs: a lower target, such as a companion
 * shown for the first time, is shown at once.
 *
 * `duration` is how long a climb takes, given how far it goes.
 */
export function useCountUp(target: number, duration: (from: number, to: number) => number) {
  const [shown, setShown] = useState(target)
  const from = useRef(target)
  const durationOf = useRef(duration)
  useEffect(() => {
    durationOf.current = duration
  })

  useEffect(() => {
    const start = from.current
    if (target <= start) {
      from.current = target
      const frame = requestAnimationFrame(() => setShown(target))
      return () => cancelAnimationFrame(frame)
    }
    const ms = Math.max(1, durationOf.current(start, target))
    const began = performance.now()
    let frame = 0
    const step = (now: number) => {
      const t = Math.min(1, (now - began) / ms)
      // Eases out, so it slows as it reaches the target.
      const value = start + (target - start) * (1 - (1 - t) ** 3)
      from.current = value
      setShown(t < 1 ? value : target)
      if (t < 1) frame = requestAnimationFrame(step)
    }
    frame = requestAnimationFrame(step)
    return () => cancelAnimationFrame(frame)
  }, [target])

  return { shown, climbing: shown < target }
}
