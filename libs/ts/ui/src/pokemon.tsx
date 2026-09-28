import Link from 'next/link'

import { CaughtIcon } from './icon'

/** A type's Korean name beside its colour, which is only ever this dot. */
export function TypeChip({ id, name }: { id: string; name: string }) {
  return (
    <span className="border-line inline-flex items-center gap-1.5 rounded border px-1.5 py-px text-xs">
      <i
        aria-hidden="true"
        className="size-2 rounded-full"
        style={{ background: `var(--type-${id})` }}
      />
      {name}
    </span>
  )
}

/** A bar beside the number it draws; a bar alone is decoration. */
export function ProgressBar({
  value,
  max,
  label,
  size = 'md',
  color = 'var(--accent)',
}: {
  value: number
  max: number
  /** Its name for screen readers: 다음 레벨까지, 부화까지. */
  label: string
  size?: 'md' | 'lg'
  color?: string
}) {
  const share = max > 0 ? Math.min(1, Math.max(0, value / max)) : 1
  return (
    <span
      role="progressbar"
      aria-label={label}
      aria-valuemin={0}
      aria-valuemax={max}
      aria-valuenow={value}
      className={`bg-surface-raised ring-line block overflow-hidden rounded-full ring-1 ring-inset ${size === 'lg' ? 'h-2' : 'h-1.5'}`}
    >
      <span
        className="block h-full rounded-full transition-[width] duration-200 motion-reduce:transition-none"
        style={{ width: `${share * 100}%`, background: color }}
      />
    </span>
  )
}

/** How far a trainer has had a pokedex entry: caught, or caught shiny too. */
export type Caught = 'caught' | 'shiny'

/**
 * A pokedex entry's marks for the trainer signed in: ✨ if they have had it
 * shiny, then the ball for having had it at all, as the games mark caught.
 */
export function CaughtMarks({ caught }: { caught: Caught }) {
  const label = caught === 'shiny' ? '색이 다른 모습까지 잡음' : '잡음'
  return (
    <span
      role="img"
      aria-label={label}
      title={label}
      className="text-muted inline-flex items-center gap-0.5 text-[11px] leading-none"
    >
      {caught === 'shiny' && <span aria-hidden="true">✨</span>}
      <CaughtIcon />
    </span>
  )
}

/**
 * A Pokémon or an egg in a list: a small sprite, its name, one line of data.
 * The whole tile is the link to its page.
 */
export function PokemonTile({
  href,
  name,
  caption,
  sprite,
  partner = false,
  shiny = false,
  task = false,
  caught,
}: {
  href: string
  name: string
  /** Lv.16 in the box, No.025 in a pokedex, tokens for an egg. */
  caption: string
  sprite?: string
  partner?: boolean
  shiny?: boolean
  /** An action waits: evolve, hatch, an egg, a ribbon. */
  task?: boolean
  /** In a pokedex, whether the trainer signed in has had it. */
  caught?: Caught
}) {
  return (
    <Link
      href={href}
      className={`bg-surface relative flex min-w-0 flex-col items-center gap-0.5 rounded-lg border px-2 pt-3 pb-2 ${partner ? 'border-accent' : 'border-line hover:border-line-strong'}`}
    >
      {partner && (
        <span className="text-accent absolute top-1 left-1.5 text-[10px] font-medium">파트너</span>
      )}
      {task && (
        <span
          title="기다리는 일이 있다"
          className="bg-accent absolute top-2 right-2 size-1.5 rounded-full"
        />
      )}
      {caught && (
        <span className="absolute top-1.5 right-1.5">
          <CaughtMarks caught={caught} />
        </span>
      )}
      {/* 96px, the sprite's own size, where the tile is wide enough; a narrow
          grid shrinks it rather than cropping it. */}
      <span className="bg-surface-raised mb-1 grid aspect-square w-full max-w-24 place-items-center rounded-md">
        {sprite && (
          // eslint-disable-next-line @next/next/no-img-element -- pixel sprites, served as they are
          <img src={sprite} alt="" className="size-full [image-rendering:pixelated]" />
        )}
      </span>
      <span className="max-w-full truncate text-[13px] font-medium">
        {shiny && <span title="색이 다른 포켓몬">✨</span>}
        {name}
      </span>
      <span className="text-muted font-mono text-[11px] tabular-nums">{caption}</span>
    </Link>
  )
}
