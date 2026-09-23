import { defineConfig } from 'vite'
import vinext from 'vinext'
import { cloudflare } from '@cloudflare/vite-plugin'
import { resolveAppVersion } from '@pokegosu/config/version'

export default defineConfig({
  // Shown by @pokegosu/ui/version-footer.
  define: { __APP_VERSION__: JSON.stringify(resolveAppVersion()) },
  plugins: [
    vinext({
      prerender: { routes: '*' },
    }),
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
