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

/** One thing said, with its own four seconds. */
function Line({ onGone, children }: { onGone: () => void; children: React.ReactNode }) {
  useEffect(() => {
    const timer = setTimeout(onGone, SHOWN_MS)
    return () => clearTimeout(timer)
    // Its four seconds start when it is said, and nothing said after resets them.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
  return (
    <p className="bg-ink text-surface pointer-events-auto max-w-task rounded-md px-4 py-2.5 text-sm font-medium">
      {children}
    </p>
  )
}

/**
 * What just happened, said for a moment over the top of the page, just under
 * the top bar, so nothing on the page moves when it comes and goes. It is the
 * one dark fill in the interface, so it stands out from the page.
 * `id` is what happened: a new one says it again, even when the words are the
 * same. What was said before stays for the rest of its four seconds, so quick
 * actions one after another are all read.
 */
export function Toast({ id, children }: { id: unknown; children: React.ReactNode }) {
  const [said, setSaid] = useState<unknown>(null)
  const [lines, setLines] = useState<{ key: number; text: React.ReactNode }[]>([])
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

  // Kept as it was when said, so a later render does not change a line on screen.
  if (id !== said) {
    setSaid(id)
    if (id != null && children != null) {
      setLines([...lines, { key: (lines.at(-1)?.key ?? 0) + 1, text: children }])
    }
  }

  return mounted && lines.length > 0
    ? createPortal(
        lines.map((line) => (
          <Line
            key={line.key}
            onGone={() => setLines((all) => all.filter((l) => l.key !== line.key))}
          >
            {line.text}
          </Line>
        )),
        stack(),
      )
    : null
}
