import { execFileSync } from 'node:child_process'

/**
 * The version an app build shows, resolved once when vite.config.ts loads.
 *
 * - On a release tag: `v0.1.0+38de1ea`.
 * - Past it: the next minor as a dev pre-release, with commits since the tag,
 *   e.g. `v0.2.0-dev.3+38de1ea`. Minor is the default guess because patch
 *   versions are kept for hotfixes.
 * - Before any tag: `v0.1.0-dev.<commits>+<hash>`.
 * - Uncommitted changes append `.dirty` to the hash.
 *
 * The version lives only in git tags; nothing in the repo is bumped by hand.
 */
export function resolveAppVersion(cwd = process.cwd()): string {
  // A CD run checks out the tag without history, and says which tag it is.
  if (process.env.GITHUB_REF_TYPE === 'tag' && process.env.GITHUB_SHA) {
    return `${process.env.GITHUB_REF_NAME}+${process.env.GITHUB_SHA.slice(0, 7)}`
  }

  const git = (...args: string[]) =>
    execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()

  try {
    const described = git(
      'describe',
      '--tags',
      '--long',
      '--dirty',
      '--abbrev=7',
      '--match',
      'v[0-9]*.[0-9]*.[0-9]*',
    )
    const match = /^v(\d+)\.(\d+)\.(\d+)-(\d+)-g([0-9a-f]+)(-dirty)?$/.exec(described)
    if (match) {
      const [, major, minor, patch, distance, hash, dirty] = match
      const build = dirty ? `${hash}.dirty` : hash
      if (distance === '0' && !dirty) return `v${major}.${minor}.${patch}+${build}`
      return `v${major}.${Number(minor) + 1}.0-dev.${distance}+${build}`
    }
  } catch {
    // No release tag reachable yet; fall through.
  }

  try {
    const hash = git('rev-parse', '--short=7', 'HEAD')
    const distance = git('rev-list', '--count', 'HEAD')
    const dirty = git('status', '--porcelain') ? '.dirty' : ''
    return `v0.1.0-dev.${distance}+${hash}${dirty}`
  } catch {
    // Not a git checkout, e.g. a source archive.
    return 'v0.0.0-unknown'
  }
}
