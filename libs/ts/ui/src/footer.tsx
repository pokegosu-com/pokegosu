// Replaced at build time by each app's vite.config.ts; see
// @pokegosu/config/version. `next dev` has no such define, hence the guard.
declare const __APP_VERSION__: string

const version = typeof __APP_VERSION__ === 'string' ? __APP_VERSION__ : 'dev'

/** Whose Pokémon these are, and the build's version, small and out of the way at the foot of every page. */
export function Footer() {
  return (
    <footer className="text-muted px-4 sm:px-6 py-4 text-center text-xs break-keep">
      <p>
        PokeGosu는 비공식·비상업 팬 프로젝트입니다. 포켓몬의 권리는 닌텐도, 게임프리크, 크리처스에
        있습니다.
      </p>
      <p className="mt-1 font-mono">{version}</p>
    </footer>
  )
}
