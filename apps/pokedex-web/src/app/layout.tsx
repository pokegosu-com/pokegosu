import type { Metadata } from 'next'

import { VersionFooter } from '@pokegosu/ui/version-footer'

import './globals.css'

export const metadata: Metadata = {
  title: 'pokedex',
  description: 'pokegosu 가 쓰는 포켓몬',
}

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="ko" className="h-full">
      <body className="bg-surface text-ink flex min-h-full flex-col antialiased">
        {children}
        <p className="text-muted mx-auto max-w-3xl px-6 pb-2 text-center text-xs">
          비공식·비상업 팬 프로젝트입니다. 포켓몬과 관련 이미지의 권리는 Nintendo, Creatures, GAME
          FREAK 에 있습니다. 스프라이트는 PokéAPI 에서 가져왔습니다.
        </p>
        <VersionFooter />
      </body>
    </html>
  )
}
