'use client'

import { MARKS, cycleMark, markOf } from '@/lib/game'

/** The six box marks, each pressed through off, blue and red. */
export function Marks({
  markings,
  onChange,
  disabled,
}: {
  markings: number
  onChange: (markings: number) => void
  disabled: boolean
}) {
  return (
    <span className="-ml-2 flex text-base leading-none lg:ml-0 lg:gap-1 lg:text-sm">
      {MARKS.map((mark, i) => {
        const color = markOf(markings, i)
        return (
          <button
            key={mark}
            type="button"
            disabled={disabled}
            onClick={() => onChange(cycleMark(markings, i))}
            className={`grid size-9 place-items-center lg:size-auto lg:p-0.5 ${color === 1 ? 'text-mark-blue' : color === 2 ? 'text-mark-red' : 'text-muted/40'}`}
            aria-label={`${mark} ${['끔', '파랑', '빨강'][color]}`}
          >
            {mark}
          </button>
        )
      })}
    </span>
  )
}
