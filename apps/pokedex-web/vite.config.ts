import { defineConfig } from 'vite'
import vinext from 'vinext'
import { cloudflare } from '@cloudflare/vite-plugin'
import { cdnAdapter } from '@vinext/cloudflare/cache/cdn-adapter'
import { resolveAppVersion } from '@pokegosu/config/version'

// Validates NEXT_PUBLIC_* at build time, the way t3-env recommends importing
// it from next.config. vinext has already loaded .env files by now.
import '@pokegosu/supabase/env'
import '@pokegosu/ui/apps'

export default defineConfig({
  // Shown by @pokegosu/ui/version-footer.
  define: { __APP_VERSION__: JSON.stringify(resolveAppVersion()) },
  plugins: [
    // Not prerendered: the pages read the pokedex from the database, which
    // a build has no business reaching. Cloudflare's edge keeps each page
    // once rendered instead, so a visit rarely reaches the Worker, whose CPU
    // time a render can use up.
    vinext({ cache: { cdn: cdnAdapter() } }),
    cloudflare({
      // Every app's dev server would otherwise take workerd's inspector on
      // 9229, so two could not run side by side. Paired with the dev port.
      inspectorPort: 9233,
      viteEnvironment: {
        name: 'rsc',
        childEnvironments: ['ssr'],
      },
    }),
  ],
})
