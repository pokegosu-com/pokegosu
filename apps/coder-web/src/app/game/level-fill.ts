'use client'

import { useEffect, useRef, useState } from 'react'

/** A level, and the tokens it starts and ends at; `to` is null at the top level. */
export type Span = { level: number; from: number; to: number | null }

/** Filling a level from empty to full takes this long; part of one, its share of it. */
const MS_PER_LEVEL = 1000

/** The level reached sits empty this long before it fills, so the new level is seen. */
const PAUSE_MS = 100

type Leg = { from: number; to: number; held: Span | null; ms: number; pause: number }

/**
 * A Pokémon's tokens filling its bar rather than jumping there, so a claim is
 * watched. A claim that gains levels fills the level it was at to full, then
 * shows the level reached, empty for a moment, and fills that: the levels
 * between are skipped, so many levels take no longer to watch than one. It
 * only ever climbs: a lower target, such as a companion shown for the first
 * time, is shown at once.
 *
 * `levelAt` is the level a number of tokens reaches, or null while the curve
 * is not known. `at` is the level to show, which is held at the old level
 * while its bar fills to full.
 */
export function useLevelFill(target: number, levelAt: (tokens: number) => Span | null) {
  const [shown, setShown] = useState<{ value: number; held: Span | null }>({
    value: target,
    held: null,
  })
  const from = useRef(target)
  const levelOf = useRef(levelAt)
  useEffect(() => {
    levelOf.current = levelAt
  })

  useEffect(() => {
    const start = from.current
    if (target <= start) {
      from.current = target
      const frame = requestAnimationFrame(() => setShown({ value: target, held: null }))
      return () => cancelAnimationFrame(frame)
    }
    const a = levelOf.current(start)
    const b = levelOf.current(target)
    const share = (s: Span, x: number, y: number) =>
      s.to === null ? 0 : ((y - x) / (s.to - s.from)) * MS_PER_LEVEL
    const legs: Leg[] =
      !a || !b
        ? [{ from: start, to: target, held: null, ms: 0, pause: 0 }]
        : a.level === b.level
          ? [{ from: start, to: target, held: null, ms: share(a, start, target), pause: 0 }]
          : [
              {
                from: start,
                to: a.to ?? target,
                held: a,
                ms: share(a, start, a.to ?? target),
                pause: 0,
              },
              {
                from: b.from,
                to: target,
                held: null,
                ms: share(b, b.from, target),
                pause: PAUSE_MS,
              },
            ]

    let leg = 0
    let began = performance.now()
    let frame = 0
    const step = (now: number) => {
      const l = legs[leg]
      const since = now - began - l.pause
      const t = since < 0 ? 0 : l.ms > 0 ? Math.min(1, since / l.ms) : 1
      const value = t < 1 ? l.from + (l.to - l.from) * t : l.to
      from.current = value
      setShown({ value, held: l.held })
      if (t < 1) {
        frame = requestAnimationFrame(step)
      } else if (++leg < legs.length) {
        began = now
        frame = requestAnimationFrame(step)
      }
    }
    frame = requestAnimationFrame(step)
    return () => cancelAnimationFrame(frame)
  }, [target])

  return {
    shown: shown.value,
    at: shown.held ?? levelAt(shown.value),
    climbing: shown.value < target || shown.held !== null,
  }
}
