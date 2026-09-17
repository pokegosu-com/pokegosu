import { defineConfig, globalIgnores } from 'eslint/config'
import nextVitals from 'eslint-config-next/core-web-vitals'
import nextTs from 'eslint-config-next/typescript'

export default defineConfig([
  ...nextVitals,
  ...nextTs,
  // eslint-config-next sets these as its defaults; restating them keeps them
  // in force now that this config wraps it.
  globalIgnores(['.next/**', 'out/**', 'next-env.d.ts']),
])
