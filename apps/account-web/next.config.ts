import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  // @pokegosu/supabase ships TypeScript source rather than a build artifact.
  transpilePackages: ['@pokegosu/supabase'],
}

export default nextConfig
