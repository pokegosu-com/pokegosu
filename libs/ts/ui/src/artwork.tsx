'use client'

import { useRef } from 'react'

/** Where a shiny one's sparkles burst, around the artwork, one after another. */
const SPARKLES = [
  { top: '14%', left: '20%', size: 18, delay: 0 },
  { top: '26%', left: '76%', size: 14, delay: 120 },
  { top: '62%', left: '12%', size: 12, delay: 240 },
  { top: '8%', left: '58%', size: 10, delay: 330 },
]

/**
 * A Pokémon's large render, in the 192px slot. The render is a still, so
 * it idles above a shadow, and hops when it appears, is pointed at or pressed;
 * a shiny one sparkles as it hops. With reduced motion it stands still.
 */
export function Artwork({
  src,
  alt,
  shiny = false,
}: {
  src?: string
  alt: string
  shiny?: boolean
}) {
  const slot = useRef<HTMLSpanElement>(null)
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
  return (
    <span
      ref={slot}
      onPointerEnter={hop}
      onClick={hop}
      className="relative grid size-48 flex-none place-items-center overflow-hidden rounded-lg"
    >
      <span className="bg-ink/10 motion-safe:animate-idle-shadow absolute bottom-4 h-3 w-24 rounded-full blur-[2px]" />
      {src && (
        // A new src, such as the shiny one, is a new image: it hops, and
        // sparkles, in.
        <span key={src} className="motion-safe:animate-idle relative">
          {/* eslint-disable-next-line @next/next/no-img-element -- large renders from pokedex-web */}
          <img
            src={src}
            alt={alt}
            className="motion-safe:animate-hop size-40 origin-bottom object-contain"
          />
          {shiny &&
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
