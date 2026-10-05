'use client'

import { CaughtMarks } from '@pokegosu/ui/pokemon'

import { useMyDex } from '@/lib/my-dex'

import { useShiny } from './shiny'

/**
 * A form's or a stage's small sprite, shiny when the page is. The page is a
 * file, so it holds both and the browser picks.
 */
export function FormSprite({ src, shiny }: { src?: string; shiny?: string }) {
  const [wantShiny] = useShiny()
  const shown = (wantShiny && shiny) || src
  if (!shown) return null
  // The slot sets the size: 96px, the sprite's own, except in the evolution
  // tree, where 56px lets four stages fit across the page.
  // eslint-disable-next-line @next/next/no-img-element -- pixel sprites, served as they are
  return <img src={shown} alt="" className="size-full [image-rendering:pixelated]" />
}

/** A form's marks, if the trainer signed in has had it; nothing otherwise. */
export function FormMarks({ id, size }: { id: number; size?: 'md' | 'lg' }) {
  const caught = useMyDex()?.forms.get(id)
  return caught ? <CaughtMarks caught={caught} size={size} /> : null
}
