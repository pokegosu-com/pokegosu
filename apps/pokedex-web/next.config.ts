import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  // @pokegosu/ui ships TypeScript source rather than a build artifact.
  transpilePackages: ['@pokegosu/ui'],
}

export default nextConfig
