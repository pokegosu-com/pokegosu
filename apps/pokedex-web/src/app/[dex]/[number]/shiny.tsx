'use client'

import { createContext, type ReactNode, useContext, useState, useSyncExternalStore } from 'react'

import { useMyDex } from '@/lib/my-dex'

const never = () => () => {}

const Shiny = createContext<[boolean, (shiny: boolean) => void]>([false, () => {}])

/**
 * Whether an entry's page draws its Pokémon shiny: every sprite on it, the
 * large one and each form's and stage's, together. One choice holds for the
 * whole page, whichever form is shown and whatever the trainer has had.
 *
 * Until it is chosen, a link that says ?shiny=1 or ?shiny=0, as the box's does
 * for one Pokémon, decides; else a trainer who has had the form the page
 * opened on shiny sees it shiny, as the list showed it.
 */
export function ShinyChoice({
  forms,
  children,
}: {
  /** Every form under this number, [slug, id], the default first. */
  forms: [string, number][]
  children: ReactNode
}) {
  const dex = useMyDex()
  // Read once the page has loaded: the file is built with no address.
  const address = useSyncExternalStore(
    never,
    () => window.location.search,
    () => '',
  )
  const query = new URLSearchParams(address)
  const opened = forms.find(([slug]) => slug === query.get('form')) ?? forms[0]
  const asked = query.get('shiny')
  const [chosen, choose] = useState<boolean | null>(null)
  const shiny = chosen ?? (asked ? asked === '1' : dex?.forms.get(opened[1]) === 'shiny')
  return <Shiny.Provider value={[shiny, choose]}>{children}</Shiny.Provider>
}

export function useShiny() {
  return useContext(Shiny)
}
