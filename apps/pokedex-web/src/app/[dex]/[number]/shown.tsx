'use client'

import { type ReactNode, useSyncExternalStore } from 'react'
import { useSearchParams } from 'next/navigation'

type Look = {
  /** Every form under this number, the default first. */
  forms: string[]
  form: string
  /** Whether this is the female's look, or null where she looks no different. */
  female: boolean | null
  children: ReactNode
}

const never = () => () => {}

/**
 * One look of an entry, shown only when the address asks for it. The page is
 * a file, the same for every ?form= and ?gender=, so the choice is made here.
 * The file holds the default look, which stands in until the page has loaded.
 */
export function Shown(look: Look) {
  // Reading the address while the file is built would leave the whole look to
  // the browser, and React reports that as an error; so it waits until then.
  const loaded = useSyncExternalStore(
    never,
    () => true,
    () => false,
  )
  if (loaded) return <Chosen {...look} />
  return look.form === look.forms[0] && !look.female ? look.children : null
}

function Chosen({ forms, form, female, children }: Look) {
  const query = useSearchParams()
  const asked = query.get('form')
  // A form this number does not have shows the default.
  const shown = asked && forms.includes(asked) ? asked : forms[0]
  if (form !== shown) return null
  if (female !== null && female !== (query.get('gender') === 'female')) return null
  return children
}
