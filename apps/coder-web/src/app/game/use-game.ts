'use client'

import { useCallback, useEffect, useRef, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

import { claimable, type Box, type Curve } from '@/lib/game'

type Action =
  | { fn: 'start_game' }
  | { fn: 'claim'; companion_id: string; tokens: number }
  | { fn: 'hatch' | 'evolve' | 'receive_egg' | 'set_main'; companion_id: string }
  | { fn: 'receive_ribbon'; companion_id: string; ribbon_id: string }
  | { fn: 'set_markings'; companion_id: string; markings: number }

/** What an action answered with; every game function answers with an outcome. */
export type Outcome = { outcome: string } & Record<string, unknown>

/**
 * The person's box, the game's experience curve, and the buttons that change
 * them.
 *
 * Opening the game is what invests tokens: the first load claims into the main
 * companion everything that fits, in one go. Watching it fill is the
 * cards' doing, counting up along the curve. Everything after that is a
 * button, and every button reloads the box, since what one changes can change
 * what others offer.
 */
export function useGame() {
  const [box, setBox] = useState<Box | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [last, setLast] = useState<{ action: Action; outcome: Outcome } | null>(null)
  const [curve, setCurve] = useState<Curve>(new Map())
  const claimedOnOpen = useRef(false)

  const load = useCallback(async () => {
    const { data, error } = await createClient().rpc('box')
    if (error) {
      setFailure(error.message)
      return
    }
    setFailure(null)
    setBox(data as Box)
  }, [])

  const act = useCallback(
    async (action: Action) => {
      setBusy(true)
      const { fn, ...args } = action
      const { data, error } = await createClient().rpc(fn, args as never)
      if (error) {
        setFailure(error.message)
      } else {
        setLast({ action, outcome: data as Outcome })
      }
      await load()
      setBusy(false)
      return error ? null : (data as Outcome)
    },
    [load],
  )

  useEffect(() => {
    let cancelled = false
    async function open() {
      const { data, error } = await createClient().rpc('box')
      if (cancelled) return
      if (error) {
        setFailure(error.message)
        return
      }
      const opened = data as Box
      setBox(opened)

      const levels = await createClient()
        .from('coder_experience_levels')
        .select('growth_rate, level, tokens')
        .order('level')
      if (cancelled) return
      if (levels.data) {
        const next: Curve = new Map()
        for (const row of levels.data) {
          next.set(row.growth_rate, [...(next.get(row.growth_rate) ?? []), row.tokens])
        }
        setCurve(next)
      }

      if (!opened.started || claimedOnOpen.current) return
      claimedOnOpen.current = true
      const tokens = claimable(opened)
      if (tokens > 0) await act({ fn: 'claim', companion_id: opened.main_companion_id, tokens })
    }
    open()
    return () => {
      cancelled = true
    }
  }, [act])

  return { box, curve, failure, busy, last, act }
}
