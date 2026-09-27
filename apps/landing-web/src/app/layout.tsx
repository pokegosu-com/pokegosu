import type { Metadata } from 'next'

import { Fonts } from '@pokegosu/ui/fonts'
import { VersionFooter } from '@pokegosu/ui/version-footer'

import './globals.css'

export const metadata: Metadata = {
  title: 'pokegosu',
  description: 'pokegosu',
}

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="ko" className="h-full">
      <head>
        <Fonts />
      </head>
      <body className="bg-surface text-ink flex min-h-full flex-col antialiased">
        {children}
        <VersionFooter />
      </body>
    </html>
  )
}
