'use client'

import { useState } from 'react'

import { Artwork } from '@pokegosu/ui/artwork'

/** The large render, with the shiny one a press away. */
export function Sprite({ name, normal, shiny }: { name: string; normal?: string; shiny?: string }) {
  const [showShiny, setShowShiny] = useState(false)
  const src = showShiny ? shiny : normal
  return (
    <div className="flex flex-none flex-col items-center gap-2">
      <Artwork src={src} alt={showShiny ? `${name} (색이 다른)` : name} shiny={showShiny} />
      {shiny && (
        <div
          role="group"
          aria-label="모습"
          className="bg-surface-raised flex gap-0.5 rounded-lg p-0.5"
        >
          {(
            [
              [false, '기본'],
              [true, '✨ 색이 다른'],
            ] as const
          ).map(([value, label]) => (
            <button
              key={label}
              type="button"
              aria-pressed={showShiny === value}
              onClick={() => setShowShiny(value)}
              className="text-muted aria-pressed:bg-surface aria-pressed:text-ink aria-pressed:ring-line rounded-md px-2.5 py-1 text-xs font-medium aria-pressed:ring-1"
            >
              {label}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}
