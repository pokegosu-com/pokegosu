'use client'

import { useRef, useState } from 'react'

/** Where a shiny one's sparkles burst, around the artwork, one after another. */
const SPARKLES = [
  { top: '14%', left: '20%', size: 18, delay: 0 },
  { top: '26%', left: '76%', size: 14, delay: 120 },
  { top: '62%', left: '12%', size: 12, delay: 240 },
  { top: '8%', left: '58%', size: 10, delay: 330 },
]

/** What a Pokémon just was: the render it evolved from, or its egg's sprite. */
export type Before = { src: string; egg?: boolean }

/**
 * A Pokémon's large render, in the 192px slot. The render is a still, so
 * it idles above a shadow, and hops when it appears, is pointed at or pressed;
 * a shiny one sparkles as it hops. With reduced motion it stands still.
 *
 * Given `from`, what it was a moment ago, it first evolves out of that render
 * or hatches out of that egg, then hops in as usual; pressing it skips to the
 * end. With reduced motion it is simply what it is now.
 */
export function Artwork({
  src,
  alt,
  shiny = false,
  from,
}: {
  src?: string
  alt: string
  shiny?: boolean
  from?: Before
}) {
  const slot = useRef<HTMLSpanElement>(null)
  // The change last played through, so the render it settled on idles and
  // hops like any other, and a later render with the same `from` does not
  // play it again.
  const change = from && src && from.src !== src ? `${from.src}>${src}` : null
  const [settled, setSettled] = useState<string | null>(null)
  const changing = from !== undefined && change !== null && change !== settled
  // Replays whatever has finished, the hop and the sparkles, and leaves the
  // idling and anything still in the air alone. With reduced motion there is
  // nothing to replay.
  const hop = () => {
    for (const animation of slot.current?.getAnimations({ subtree: true }) ?? []) {
      if (animation.playState === 'running') continue
      animation.cancel()
      animation.play()
    }
  }
  // Ends an evolution or a hatching at once. The idling never ends, and
  // finishing it would throw.
  const skip = () => {
    for (const animation of slot.current?.getAnimations({ subtree: true }) ?? []) {
      if (animation.effect?.getTiming().iterations === Infinity) continue
      animation.finish()
    }
  }
  return (
    <span
      ref={slot}
      onPointerEnter={changing ? undefined : hop}
      onClick={changing ? skip : hop}
      className="relative grid size-48 flex-none place-items-center overflow-hidden rounded-lg"
    >
      <span className="bg-ink/10 motion-safe:animate-idle-shadow absolute bottom-4 h-3 w-24 rounded-full blur-[2px]" />
      {src && (
        // A new src, such as the shiny one, is a new image: it hops, and
        // sparkles, in.
        <span key={src} className="motion-safe:animate-idle relative">
          {changing && (
            // What it was, laid over it; only the motion shows it.
            // eslint-disable-next-line @next/next/no-img-element -- renders and the egg from pokedex-web
            <img
              src={from.src}
              alt=""
              aria-hidden
              className={
                from.egg
                  ? 'motion-safe:animate-hatch-out absolute inset-0 m-auto hidden size-24 origin-bottom [image-rendering:pixelated] motion-safe:block'
                  : 'motion-safe:animate-evolve-out absolute inset-0 hidden size-40 object-contain motion-safe:block'
              }
            />
          )}
          {/* eslint-disable-next-line @next/next/no-img-element -- large renders from pokedex-web */}
          <img
            src={src}
            alt={alt}
            // Once it has evolved or hatched it hops in, as any new render does.
            onAnimationEnd={(e) => {
              if (changing && e.target === e.currentTarget) setSettled(change)
            }}
            className={`size-40 origin-bottom object-contain ${
              !changing
                ? 'motion-safe:animate-hop'
                : from.egg
                  ? 'motion-safe:animate-hatch-in'
                  : 'motion-safe:animate-evolve-in'
            }`}
          />
          {shiny &&
            !changing &&
            SPARKLES.map((s) => (
              <svg
                key={`${s.top}-${s.left}`}
                viewBox="0 0 16 16"
                aria-hidden
                className="text-sparkle motion-safe:animate-sparkle absolute hidden motion-safe:block"
                style={{
                  top: s.top,
                  left: s.left,
                  width: s.size,
                  height: s.size,
                  animationDelay: `${s.delay}ms`,
                }}
              >
                <path d="M8 0 9.6 6.4 16 8 9.6 9.6 8 16 6.4 9.6 0 8 6.4 6.4Z" fill="currentColor" />
              </svg>
            ))}
        </span>
      )}
    </span>
  )
}
