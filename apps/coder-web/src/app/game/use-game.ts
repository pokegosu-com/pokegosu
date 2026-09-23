'use client'

import { useCallback, useEffect, useRef, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

import type { Box } from '@/lib/game'

type Action =
  | { fn: 'start_game' }
  | { fn: 'claim' | 'hatch' | 'evolve' | 'receive_egg' | 'set_main'; companion_id: string }
  | { fn: 'receive_ribbon'; companion_id: string; ribbon_id: string }
  | { fn: 'set_markings'; companion_id: string; markings: number }

/** What an action answered with; every game function answers with an outcome. */
export type Outcome = { outcome: string } & Record<string, unknown>

/**
 * The person's box, and the buttons that change it.
 *
 * Opening the game is what invests tokens: the first load claims into the main
 * companion once. Everything after that is a button, and every button reloads
 * the box, since what one changes can change what others offer.
 */
export function useGame() {
  const [box, setBox] = useState<Box | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [last, setLast] = useState<{ action: Action; outcome: Outcome } | null>(null)
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
      if (!opened.started || claimedOnOpen.current) return
      claimedOnOpen.current = true
      await act({ fn: 'claim', companion_id: opened.main_companion_id })
    }
    open()
    return () => {
      cancelled = true
    }
  }, [act])

  return { box, failure, busy, last, act }
}
