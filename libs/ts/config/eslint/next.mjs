import { defineConfig, globalIgnores } from 'eslint/config'
import nextVitals from 'eslint-config-next/core-web-vitals'
import nextTs from 'eslint-config-next/typescript'

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  // eslint-config-next sets the first three as its defaults; restating them
  // keeps them in force now that this config wraps it. The rest is vinext
  // build output — gitignored, so Prettier skips it, but eslint reads neither
  // .gitignore nor .prettierignore and would walk it.
  globalIgnores(['.next/**', 'out/**', 'next-env.d.ts', 'dist/**', '.vinext/**', '.wrangler/**']),
])
