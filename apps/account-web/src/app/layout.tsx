import type { Metadata } from 'next'

import './globals.css'

export const metadata: Metadata = {
  title: 'pokegosu · 계정',
  description: 'pokegosu account',
}

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="ko" className="h-full">
      <body className="bg-surface text-ink min-h-full antialiased">{children}</body>
    </html>
  )
}
