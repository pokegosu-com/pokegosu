import { env } from '@/env'

// Inlined at build time, so the page stays static. The account app decides what
// to do with a visitor who is already signed in, which is why this link does
// not need to know anything about the session.
const accountUrl = env.NEXT_PUBLIC_ACCOUNT_URL

export default function Home() {
  return (
    <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col justify-center gap-8 px-6 py-24">
      <div className="space-y-3">
        <h1 className="text-4xl font-semibold tracking-tight">pokegosu</h1>
        <p className="text-muted text-lg">소개 문구가 들어갈 자리입니다.</p>
      </div>

      <div>
        <a
          href={`${accountUrl}/login`}
          className="bg-accent text-surface inline-block rounded-md px-4 py-2 text-sm font-medium"
        >
          로그인
        </a>
      </div>
    </main>
  )
}
