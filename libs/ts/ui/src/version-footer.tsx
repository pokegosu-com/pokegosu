// Replaced at build time by each app's vite.config.ts; see
// @pokegosu/config/version. `next dev` has no such define, hence the guard.
declare const __APP_VERSION__: string

const version = typeof __APP_VERSION__ === 'string' ? __APP_VERSION__ : 'dev'

/** The build's version, small and out of the way at the foot of every page. */
export function VersionFooter() {
  return <footer className="text-muted px-6 py-4 text-center font-mono text-xs">{version}</footer>
}
