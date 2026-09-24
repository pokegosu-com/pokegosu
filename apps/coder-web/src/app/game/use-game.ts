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

/** How long a claim waits for the one before it to sink in. */
const CLAIM_PAUSE_MS = 1000

/**
 * The person's box, and the buttons that change it.
 *
 * Opening the game is what invests tokens: the first load claims into the main
 * companion, a claim a second for as long as anything fits, so a day's work
 * arrives as a run of level-ups to watch rather than all at once. That pace is
 * the only reason a claim has a limit. Everything after that is a button, and
 * every button reloads the box, since what one changes can change what others
 * offer.
 */
export function useGame() {
  const [box, setBox] = useState<Box | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [last, setLast] = useState<{ action: Action; outcome: Outcome } | null>(null)
  const claimedOnOpen = useRef(false)
  const claiming = useRef(false)
  const mounted = useRef(true)

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

  /** Claims into the main one a second at a time, until nothing more fits. */
  const claimAll = useCallback(
    async (companion_id: string) => {
      if (claiming.current) return
      claiming.current = true
      try {
        while (mounted.current) {
          const outcome = await act({ fn: 'claim', companion_id })
          if (outcome?.outcome !== 'claimed') break
          await new Promise((resolve) => setTimeout(resolve, CLAIM_PAUSE_MS))
        }
      } finally {
        claiming.current = false
      }
    },
    [act],
  )

  useEffect(() => {
    mounted.current = true
    return () => {
      mounted.current = false
    }
  }, [])

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
      await claimAll(opened.main_companion_id)
    }
    open()
    return () => {
      cancelled = true
    }
  }, [claimAll])

  return { box, failure, busy, last, act, claimAll }
}
