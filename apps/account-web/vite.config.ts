import { defineConfig } from 'vite'
import vinext from 'vinext'
import { cloudflare } from '@cloudflare/vite-plugin'
import { resolveAppVersion } from '@pokegosu/config/version'

// Validates NEXT_PUBLIC_* at build time, the way t3-env recommends importing
// it from next.config. vinext has already loaded .env files by now.
import '@pokegosu/supabase/env'

export default defineConfig({
  // Shown by @pokegosu/ui/version-footer.
  define: { __APP_VERSION__: JSON.stringify(resolveAppVersion()) },
  plugins: [
    vinext(),
    cloudflare({
      viteEnvironment: {
        name: 'rsc',
        childEnvironments: ['ssr'],
      },
    }),
  ],
})
