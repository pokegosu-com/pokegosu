'use client'

import { useState, useSyncExternalStore } from 'react'

import { Artwork } from '@pokegosu/ui/artwork'

import { useMyDex } from '@/lib/my-dex'

const never = () => () => {}

/**
 * The large render, with the shiny one a press away. A trainer who has had
 * this form shiny sees it shiny first, as the list showed it; a link that
 * says ?shiny=1 or ?shiny=0, as the box's does for one Pokémon, says first.
 */
export function Sprite({
  id,
  name,
  normal,
  shiny,
}: {
  /** The form, to look up in the trainer's pokedex. */
  id: number
  name: string
  normal?: string
  shiny?: string
}) {
  const hadShiny = useMyDex()?.forms.get(id) === 'shiny'
  // Read once the page has loaded: the file is built with no address. Choosing
  // another form drops it from the address, and that form goes by the pokedex.
  const asked = useSyncExternalStore(
    never,
    () => new URLSearchParams(window.location.search).get('shiny'),
    () => null,
  )
  const [chosen, setShowShiny] = useState<boolean | null>(null)
  const showShiny = !!shiny && (chosen ?? (asked ? asked === '1' : hadShiny))
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
