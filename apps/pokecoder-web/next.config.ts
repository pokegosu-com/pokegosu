import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  // These ship TypeScript source rather than a build artifact.
  transpilePackages: ['@pokegosu/supabase', '@pokegosu/ui'],
}

export default nextConfig
