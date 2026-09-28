'use client'

import { CaughtMarks } from '@pokegosu/ui/pokemon'

import { useMyDex } from '@/lib/my-dex'

/** A form's marks, if the trainer signed in has had it; nothing otherwise. */
export function FormMarks({ id, size }: { id: number; size?: 'md' | 'lg' }) {
  const caught = useMyDex()?.forms.get(id)
  return caught ? <CaughtMarks caught={caught} size={size} /> : null
}
