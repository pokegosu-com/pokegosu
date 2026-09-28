'use client'

import { CaughtMarks } from '@pokegosu/ui/pokemon'

import { useMyDex } from '@/lib/my-dex'

/**
 * A form's small sprite, shiny where the trainer signed in has had it shiny.
 * The page is a file, so it holds both and the browser picks.
 */
export function FormSprite({ id, src, shiny }: { id: number; src?: string; shiny?: string }) {
  const hadShiny = useMyDex()?.forms.get(id) === 'shiny'
  const shown = (hadShiny && shiny) || src
  if (!shown) return null
  // eslint-disable-next-line @next/next/no-img-element -- pixel sprites, served as they are
  return <img src={shown} alt="" className="size-24 [image-rendering:pixelated]" />
}

/** A form's marks, if the trainer signed in has had it; nothing otherwise. */
export function FormMarks({ id, size }: { id: number; size?: 'md' | 'lg' }) {
  const caught = useMyDex()?.forms.get(id)
  return caught ? <CaughtMarks caught={caught} size={size} /> : null
}
