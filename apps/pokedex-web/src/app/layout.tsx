import type { Metadata } from 'next'

import { AppHeader } from '@pokegosu/ui/app-shell'
import { Fonts } from '@pokegosu/ui/fonts'
import { VersionFooter } from '@pokegosu/ui/version-footer'

import { DEXES, ko, pokedex } from '@/lib/pokedex'

import './globals.css'

export const metadata: Metadata = {
  title: 'PokeGosu Pokédex',
  description: '포켓몬 찾아보기',
}

export default async function RootLayout({ children }: LayoutProps<'/'>) {
  const { data: kinds, error } = await pokedex()
    .from('pokedex_kinds')
    .select('id, ko_name, en_name')
  if (error) throw error
  // Each pokedex is a section, so an entry's page still shows which one it is in.
  const sections = DEXES.flatMap((id) => {
    const kind = kinds.find((k) => k.id === id)
    return kind ? [{ label: ko(kind), href: `/${id}` }] : []
  })

  return (
    <html lang="ko" className="h-full">
      <head>
        <Fonts />
      </head>
      <body className="bg-surface text-ink flex min-h-full flex-col antialiased">
        <AppHeader app="pokedex" name="PokeGosu Pokédex" sections={sections} />
        {children}
        <p className="text-muted max-w-wide mx-auto px-6 pb-2 text-center text-xs">
          비공식·비상업 팬 프로젝트입니다. 포켓몬과 관련 이미지의 권리는 Nintendo, Creatures, GAME
          FREAK 에 있습니다. 스프라이트는 PokéAPI 에서 가져왔습니다.
        </p>
        <VersionFooter />
      </body>
    </html>
  )
}
