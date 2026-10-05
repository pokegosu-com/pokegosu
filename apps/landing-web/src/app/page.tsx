import { apps } from '@pokegosu/ui/apps'
import { PokeGosuIcon } from '@pokegosu/ui/icon'

import { env } from '@/env'

// Inlined at build time, so the page stays static. The account app decides what
// to do with a visitor who is already signed in, which is why this link does
// not need to know anything about the session.
const accountUrl = env.NEXT_PUBLIC_ACCOUNT_URL

const blurbs: Record<(typeof apps)[number]['id'], string> = {
  pokedex: '포켓몬의 타입과 진화를 찾아봅니다.',
  coder: '코딩 에이전트가 쓴 토큰으로 포켓몬을 키웁니다.',
}

export default function Home() {
  return (
    <main className="mx-auto max-w-2xl flex w-full flex-1 flex-col gap-10 px-4 pt-10 pb-16 sm:justify-center sm:px-6 sm:py-24">
      <div className="space-y-3">
        <h1 className="flex items-center gap-3 text-4xl font-semibold tracking-tight">
          <PokeGosuIcon size={40} />
          PokeGosu
        </h1>
        <p className="text-muted text-lg">트레이너를 위한 포켓몬 앱 모음.</p>
      </div>

      <ul className="grid gap-3 sm:grid-cols-2">
        {apps.map((app) => (
          <li key={app.id} className="grid">
            <a
              href={app.url}
              className="border-line hover:border-line-strong flex flex-col gap-2 rounded-lg border p-5"
            >
              <span className="font-semibold">{app.name}</span>
              <span className="text-muted text-sm">{blurbs[app.id]}</span>
              <span className="text-muted font-mono text-xs">{new URL(app.url).host}</span>
            </a>
          </li>
        ))}
      </ul>

      <div>
        <a
          href={`${accountUrl}/login`}
          className="bg-accent text-surface block rounded-md px-4 py-2.5 text-center text-sm font-medium sm:inline-block"
        >
          로그인
        </a>
      </div>
    </main>
  )
}
