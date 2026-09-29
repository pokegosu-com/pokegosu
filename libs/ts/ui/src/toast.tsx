'use client'

import { useEffect, useState, useSyncExternalStore } from 'react'
import { createPortal } from 'react-dom'

/** Long enough to read a line of Korean twice. */
const SHOWN_MS = 4000

/**
 * Where every toast on the page lands, one under another, so two said at once
 * are both read. It is one live region for the page, made on first use.
 */
function stack(): HTMLElement {
  let el = document.getElementById('toasts')
  if (!el) {
    el = document.createElement('div')
    el.id = 'toasts'
    el.setAttribute('role', 'status')
    el.setAttribute('aria-live', 'polite')
    el.className =
      'pointer-events-none fixed inset-x-0 top-20 z-50 flex flex-col items-center gap-2 px-6'
    document.body.append(el)
  }
  return el
}

const noop = () => () => {}

/**
 * What just happened, said for a moment over the top of the page, just under
 * the top bar, so nothing on the page moves when it comes and goes. It is the
 * one dark fill in the interface, so it stands out from the page.
 * `id` is what happened: a new one says it again, even when the words are the
 * same.
 */
export function Toast({ id, children }: { id: unknown; children: React.ReactNode }) {
  const [gone, setGone] = useState<unknown>(null)
  // The stack is the document's, so it is only there once the page runs.
  const mounted = useSyncExternalStore(
    noop,
    () => true,
    () => false,
  )

  // Made before anything is said in it, so a screen reader hears the first.
  useEffect(() => {
    stack()
  }, [])

  useEffect(() => {
    if (id == null) return
    const timer = setTimeout(() => setGone(id), SHOWN_MS)
    return () => clearTimeout(timer)
  }, [id])

  const shown = mounted && id != null && children != null && gone !== id
  return shown
    ? createPortal(
        <p className="bg-ink text-surface pointer-events-auto max-w-task rounded-md px-4 py-2.5 text-sm font-medium">
          {children}
        </p>,
        stack(),
      )
    : null
}
