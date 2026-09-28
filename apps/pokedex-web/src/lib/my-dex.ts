'use client'

import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'
import type { Caught } from '@pokegosu/ui/pokemon'

export type MyDex = {
  /** By form: what the trainer has had of it. */
  forms: Map<number, Caught>
  /** By a species' default form, so a list's one tile stands for every form. */
  species: Map<number, { caught: Caught; shinyFront?: string }>
}

let asked: Promise<MyDex | null> | undefined

/**
 * Every page is built ahead as a file, the same for everyone, so what the
 * trainer signed in has had is asked for here, in the browser, once a load.
 * A visitor with no session asks nothing and gets null.
 */
function ask(): Promise<MyDex | null> {
  asked ??= (async () => {
    const supabase = createClient()
    const {
      data: { session },
    } = await supabase.auth.getSession()
    if (!session) return null
    const { data, error } = await supabase.rpc('my_dex')
    if (error) throw error

    const forms = new Map<number, Caught>()
    const species: MyDex['species'] = new Map()
    for (const row of data) {
      const caught: Caught = row.shiny ? 'shiny' : 'caught'
      forms.set(row.species_id, caught)
      const had = species.get(row.default_id)
      // The default form's shiny sprite first, else any shiny form's.
      const shinyFront =
        row.shiny && (row.species_id === row.default_id || !had?.shinyFront)
          ? (row.shiny_front ?? had?.shinyFront)
          : had?.shinyFront
      species.set(row.default_id, {
        caught: had?.caught === 'shiny' ? 'shiny' : caught,
        shinyFront: shinyFront ?? undefined,
      })
    }
    return { forms, species }
  })()
  return asked
}

/** The trainer's pokedex, or null for a visitor and until it has come. */
export function useMyDex(): MyDex | null {
  const [dex, setDex] = useState<MyDex | null>(null)
  useEffect(() => {
    let current = true
    ask().then(
      (found) => current && setDex(found),
      // The marks are an extra on a page that works without them; the page
      // says nothing, and the next load asks again.
      (error) => {
        asked = undefined
        console.error(error)
      },
    )
    return () => {
      current = false
    }
  }, [])
  return dex
}
