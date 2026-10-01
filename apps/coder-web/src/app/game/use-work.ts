'use client'

import { useCallback, useEffect, useRef, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

import type { Work } from '@/lib/game'

import type { Outcome } from './use-game'

export type WorkAction =
  | { fn: 'assign'; workplace_id: string; companion_id: string }
  | { fn: 'settle' | 'reroll'; workplace_id: string }
  | { fn: 'settle_trainer' }

/** The last action, what it answered, and the workplaces as they were before it, for who it was. */
export type WorkLast = { action: WorkAction; outcome: Outcome; before: Work | null }

/**
 * The person's workplaces and the buttons that change them. As with the box,
 * every button reloads the lot: settling one changes the points and frees a
 * Pokémon another could take.
 */
export function useWork() {
  const [work, setWork] = useState<Work | null>(null)
  const [failure, setFailure] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [last, setLast] = useState<WorkLast | null>(null)
  const current = useRef<Work | null>(null)
  useEffect(() => {
    current.current = work
  })

  const load = useCallback(async () => {
    const { data, error } = await createClient().rpc('work')
    if (error) {
      setFailure(error.message)
      return
    }
    setFailure(null)
    setWork(data as Work)
  }, [])

  const act = useCallback(
    async (action: WorkAction) => {
      setBusy(true)
      const before = current.current
      const { fn, ...args } = action
      const { data, error } = await createClient().rpc(fn, args as never)
      if (error) setFailure(error.message)
      else setLast({ action, outcome: data as Outcome, before })
      await load()
      setBusy(false)
    },
    [load],
  )

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- the first load, as the box does
    load()
  }, [load])

  return { work, failure, busy, last, act }
}
