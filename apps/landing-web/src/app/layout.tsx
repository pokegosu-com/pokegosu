import type { Metadata } from 'next'

import { Fonts } from '@pokegosu/ui/fonts'
import { faviconUrl } from '@pokegosu/ui/icon'
import { VersionFooter } from '@pokegosu/ui/version-footer'

import './globals.css'

export const metadata: Metadata = {
  title: 'PokeGosu',
  description: '트레이너를 위한 포켓몬 앱 모음',
  icons: { icon: faviconUrl },
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
