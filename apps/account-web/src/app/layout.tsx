import type { Metadata } from 'next'

import { AppHeader } from '@pokegosu/ui/app-shell'
import { Fonts } from '@pokegosu/ui/fonts'
import { faviconUrl } from '@pokegosu/ui/icon'
import { VersionFooter } from '@pokegosu/ui/version-footer'

import './globals.css'

export const metadata: Metadata = {
  title: 'PokeGosu 계정',
  description: 'PokeGosu 계정과 기기',
  icons: { icon: faviconUrl },
}

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="ko" className="h-full">
      <head>
        <Fonts />
      </head>
      <body className="bg-surface text-ink flex min-h-full flex-col antialiased">
        <AppHeader
          app="account"
          name="PokeGosu 계정"
          sections={[
            { label: '프로필', href: '/' },
            { label: '기기', href: '/devices' },
          ]}
          bareOn={['/login', '/onboarding']}
        />
        {children}
        <VersionFooter />
      </body>
    </html>
  )
}
