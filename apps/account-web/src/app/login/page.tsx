import { safeReturnTo } from '@/lib/return-to'

import { LoginForm } from './login-form'

export default async function LoginPage({ searchParams }: PageProps<'/login'>) {
  const params = await searchParams
  const error = typeof params.error === 'string' ? params.error : null
  const returnTo = safeReturnTo(typeof params.next === 'string' ? params.next : null)

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-6 px-6 py-24">
      <div className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">로그인</h1>
        <p className="text-muted text-sm">
          계정이 없으면 이 링크로 자동 생성됩니다. 비밀번호는 없습니다.
        </p>
      </div>

      {error && <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">{error}</p>}

      <LoginForm returnTo={returnTo} />
    </main>
  )
}
