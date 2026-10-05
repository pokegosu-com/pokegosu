import { dexNo } from '@/lib/pokedex'

import { FormMarks, FormSprite } from './marks'
import { StageLink } from './shiny'

/** One stage of a family, with what it takes to reach and what it becomes. */
export type Stage = {
  id: number
  href: string
  name: string
  /** A form's name under its species', as Alolan Raichu's. */
  form: string | null
  number: number
  front?: string
  shiny?: string
  /** What evolving into it takes; null for the first stage shown. */
  method: string | null
  next: Stage[]
}

/**
 * A family's evolutions as a tree. On a phone it reads top to bottom, each
 * stage set in under the one it comes from. From sm it runs left to right,
 * branches stacked, each stage's top level with its first evolution's, so
 * Eevee sits beside Vaporeon rather than halfway down eight.
 *
 * Every connector meets a card 35px below its top, half the card's 70px.
 */
export function Family({ stages, current }: { stages: Stage[]; current: number }) {
  return (
    <div className="overflow-x-auto pb-2">
      <ul className="flex flex-col gap-2">
        {stages.map((s) => (
          <li key={s.id}>
            <Node stage={s} current={current} />
          </li>
        ))}
      </ul>
    </div>
  )
}

function Node({ stage: s, current }: { stage: Stage; current: number }) {
  return (
    <div className="flex flex-col sm:flex-row sm:items-start">
      <StageLink
        href={s.href}
        aria-current={s.id === current ? 'page' : undefined}
        className="border-line hover:border-line-strong aria-[current=page]:border-accent relative flex min-h-[70px] w-full max-w-68 items-center gap-2 rounded-lg border px-2 py-1.5 text-[13px] sm:w-40 sm:shrink-0"
      >
        <span className="absolute top-1 right-1">
          <FormMarks id={s.id} />
        </span>
        <span className="grid size-14 shrink-0 place-items-center">
          <FormSprite src={s.front} shiny={s.shiny} />
        </span>
        <span className="flex min-w-0 flex-col pr-4 leading-[1.3] break-keep wrap-anywhere">
          {s.name}
          {s.form && <span className="text-muted text-[11px]">{s.form}</span>}
          <span className="text-muted mt-0.5 font-mono text-[11px]">{dexNo(s.number)}</span>
        </span>
      </StageLink>
      {s.next.length > 0 && (
        // From sm the branches share one grid, so every arrow out of a stage
        // is as wide as its longest label and the cards after them line up.
        <ul className="sm:before:border-line-strong relative pl-7 sm:grid sm:grid-cols-[auto_auto] sm:gap-y-2 sm:pl-3 sm:before:absolute sm:before:top-[35px] sm:before:left-0 sm:before:w-3 sm:before:border-t">
          {s.next.map((n) => (
            // The rail down the left and the elbow into each: on a phone to
            // the line that says what it takes, from sm to the card's middle.
            <li
              key={n.id}
              className="before:border-line-strong after:border-line-strong relative pt-2 pl-5 before:absolute before:inset-y-0 before:left-0 before:border-l after:absolute after:top-[18px] after:left-0 after:w-3.5 after:border-t last:before:bottom-auto last:before:h-[18px] sm:col-span-2 sm:grid sm:grid-cols-subgrid sm:items-start sm:pt-0 sm:pl-0 sm:before:-inset-y-1 sm:after:hidden sm:first:before:top-[35px] sm:last:before:bottom-auto sm:last:before:h-[39px] sm:only:before:hidden"
            >
              {/* Drawn even with nothing to say, for the arrow from sm. The
                  label sits above the arrow rather than on it, so a long one,
                  as a Mega Evolution's, never hides it. */}
              <span className="text-muted mb-1 block text-xs leading-5 sm:before:border-line-strong sm:after:border-l-line-strong sm:relative sm:mb-0 sm:flex sm:h-[70px] sm:max-w-40 sm:min-w-24 sm:flex-col sm:justify-end sm:pr-2.5 sm:pb-[39px] sm:pl-1 sm:leading-[1.3] sm:before:absolute sm:before:top-[35px] sm:before:right-1 sm:before:left-0 sm:before:border-t sm:after:absolute sm:after:top-[31px] sm:after:right-0.5 sm:after:border-y-4 sm:after:border-l-6 sm:after:border-y-transparent">
                <span className="break-keep wrap-anywhere sm:text-center">{n.method}</span>
              </span>
              <Node stage={n} current={current} />
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}
