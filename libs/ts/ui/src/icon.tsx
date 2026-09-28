import { useId } from 'react'

const CAP_AT = 'translate(14.5 10.17) rotate(-10) scale(1.2 1.02) translate(-13 -21.5)'

/**
 * PokeGosu's icon, a Poké Ball in a trainer's cap, as SVG markup in
 * `currentColor`. The favicon and the page both draw from this one string, so
 * the two cannot drift. Mask ids are document-wide, so each copy on a page
 * prefixes them.
 */
function markup(id: string) {
  return `<defs>
  <g id="${id}cap">
    <ellipse cx="13.2" cy="6.2" rx="1.7" ry="2"/>
    <path d="M1.5 23.5C1 14.5 6 7.6 13.5 7.6C20.5 7.6 24.6 12.4 25 19.4Z"/>
    <path d="M19.5 20.2C24 18.6 28.6 19 31.4 21C31 23.4 27.4 24.6 22.6 24.4C19 24.2 16 23 12.5 21.6Z"/>
  </g>
  <mask id="${id}under-cap" maskUnits="userSpaceOnUse" x="-20" y="-20" width="72" height="72">
    <rect x="-20" y="-20" width="72" height="72" fill="#fff"/>
    <use href="#${id}cap" transform="${CAP_AT}" stroke="#000" stroke-width="2.04" stroke-linejoin="round"/>
  </mask>
  <mask id="${id}bill-gap" maskUnits="userSpaceOnUse" x="-20" y="-20" width="72" height="72">
    <rect x="-20" y="-20" width="72" height="72" fill="#fff"/>
    <path d="M19.2 19.6C24 18 28.6 18.4 31.6 20.4" fill="none" stroke="#000" stroke-width="1.2"/>
  </mask>
</defs>
<g fill="none" stroke="currentColor" stroke-width="2.6" mask="url(#${id}under-cap)">
  <circle cx="16" cy="16" r="10.6"/>
  <path d="M5.4 16H12.6M19.4 16H26.6"/>
  <circle cx="16" cy="16" r="3.2"/>
</g>
<use href="#${id}cap" transform="${CAP_AT}" fill="currentColor" mask="url(#${id}bill-gap)"/>`
}

const VIEW_BOX = '-1 -8.3 37.8 37.8'

/**
 * The favicon, for each app's `metadata.icons`. It is `ink`, light under a dark
 * scheme as the page's is, written as hex since not everything that reads a
 * favicon knows oklch.
 */
export const faviconUrl = `data:image/svg+xml,${encodeURIComponent(
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${VIEW_BOX}">` +
    '<style>svg{color:#181818}@media (prefers-color-scheme:dark){svg{color:#f5f5f5}}</style>' +
    markup('') +
    '</svg>',
)}`

/** The icon on the page, in the colour of the text around it. */
export function PokeGosuIcon({ size = 20 }: { size?: number }) {
  const id = useId()
  return (
    <svg
      width={size}
      height={size}
      viewBox={VIEW_BOX}
      aria-hidden="true"
      // The markup is this module's own constant, never anything from outside.
      dangerouslySetInnerHTML={{ __html: markup(id) }}
    />
  )
}

/**
 * A Poké Ball, as the games mark a pokedex entry the trainer has caught. The
 * same ball as PokeGosu's icon, without the cap, drawn thin to sit beside text.
 */
export function CaughtIcon({ size = 12 }: { size?: number }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 16 16"
      aria-hidden="true"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
    >
      <circle cx="8" cy="8" r="6.25" />
      <path d="M1.75 8H6M10 8H14.25" />
      <circle cx="8" cy="8" r="2" />
    </svg>
  )
}
