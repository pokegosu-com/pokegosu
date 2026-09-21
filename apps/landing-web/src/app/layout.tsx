import type { Metadata } from 'next'

import { VersionFooter } from '@pokegosu/ui/version-footer'

import './globals.css'

export const metadata: Metadata = {
  title: 'pokegosu',
  description: 'pokegosu',
}

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="ko" className="h-full">
      <body className="bg-surface text-ink flex min-h-full flex-col antialiased">
        {children}
        <VersionFooter />
      </body>
    </html>
  )
}
