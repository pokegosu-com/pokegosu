import type { Metadata } from 'next'
import Link from 'next/link'

import { VersionFooter } from '@pokegosu/ui/version-footer'

import './globals.css'

export const metadata: Metadata = {
  title: 'pokegosu · 계정',
  description: 'pokegosu account',
}

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="ko" className="h-full">
      <body className="bg-surface text-ink flex min-h-full flex-col antialiased">
        <header className="border-muted/25 border-b">
          <nav className="mx-auto flex w-full max-w-3xl items-center gap-6 px-6 py-4 text-sm">
            <Link href="/" className="font-semibold tracking-tight">
              pokegosu
            </Link>
            <Link href="/devices" className="text-muted hover:text-ink">
              기기
            </Link>
          </nav>
        </header>
        {children}
        <VersionFooter />
      </body>
    </html>
  )
}
