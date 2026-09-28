import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  // Every page is a file, built from the database: a render on a request
  // ran out of the Worker's CPU time. Cloudflare serves a file before the
  // Worker, which is left only the addresses no file has, such as / and a
  // page that does not exist.
  output: 'export',
  // These ship TypeScript source rather than a build artifact.
  transpilePackages: ['@pokegosu/supabase', '@pokegosu/ui'],
}

export default nextConfig
