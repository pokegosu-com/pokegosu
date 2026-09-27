import type { Metadata } from 'next'

import { AppHeader } from '@pokegosu/ui/app-shell'
import { Fonts } from '@pokegosu/ui/fonts'
import { VersionFooter } from '@pokegosu/ui/version-footer'

import './globals.css'

export const metadata: Metadata = {
  title: 'PokeGosu Coder',
  description: '코딩 에이전트 토큰으로 포켓몬 키우기',
}

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="ko" className="h-full">
      <head>
        <Fonts />
      </head>
      <body className="bg-surface text-ink flex min-h-full flex-col antialiased">
        {/* Machines are the account's; Coder only reads what they sent. */}
        <AppHeader
          app="coder"
          name="PokeGosu Coder"
          sections={[
            { label: '대시보드', href: '/' },
            { label: '박스', href: '/box' },
            { label: '사용량', href: '/usage' },
          ]}
        />
        {children}
        <VersionFooter />
      </body>
    </html>
  )
}
