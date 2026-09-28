'use client'

import { type ComponentProps, type ReactNode, useSyncExternalStore } from 'react'
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

/**
 * A link to another look of the same entry. Every look is already on the page,
 * so a press only changes the address, which vinext passes to useSearchParams
 * without fetching or rendering the page again. The address is replaced, not
 * added to: it can still be shared, but going back leaves the entry rather
 * than stepping through every look tried. Opening it in a new tab, or any
 * press but a plain one, still follows it as a link.
 */
export function LookLink({ href, ...props }: ComponentProps<'a'> & { href: string }) {
  return (
    <a
      href={href}
      {...props}
      onClick={(event) => {
        if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)
          return
        event.preventDefault()
        // Another form keeps the page's shiny choice.
        const url = new URL(href, window.location.href)
        const shiny = new URLSearchParams(window.location.search).get('shiny')
        if (shiny) url.searchParams.set('shiny', shiny)
        window.history.replaceState(null, '', url)
      }}
    />
  )
}
