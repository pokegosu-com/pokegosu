import { redirect } from 'next/navigation'

import { createClient } from '@/lib/supabase/server'

import { DisplayName } from './display-name'

export default async function AccountPage() {
  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  // proxy.ts already turns anonymous visitors away; this keeps the page correct
  // on its own rather than trusting an upstream check.
  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('username, display_name')
    .eq('id', user.id)
    .single()

  if (!profile?.username) redirect('/onboarding')

  return (
    <main className="max-w-wide mx-auto flex w-full flex-1 flex-col gap-8 px-4 sm:px-6 py-10">
      <header className="space-y-1">
        {/* Never null beside a handle; the column is nullable only for before one. */}
        <DisplayName
          userId={user.id}
          displayName={profile.display_name ?? `@${profile.username}`}
        />
        <p className="text-muted font-mono text-[13px]">@{profile.username}</p>
      </header>

      <dl className="border-line border-t text-sm">
        <div className="border-line grid grid-cols-[10rem_minmax(0,1fr)] gap-4 border-b py-3.5">
          <dt className="text-muted">이메일</dt>
          <dd>{user.email}</dd>
        </div>
        <div className="border-line grid grid-cols-[10rem_minmax(0,1fr)] gap-4 border-b py-3.5">
          <dt className="text-muted">가입일</dt>
          <dd className="font-mono text-[13px]">
            {new Date(user.created_at).toLocaleDateString('ko-KR')}
          </dd>
        </div>
      </dl>

      <form action="/auth/signout" method="post">
        <button
          type="submit"
          className="border-line-strong hover:border-ink rounded-md border px-4 py-2 text-sm font-medium"
        >
          로그아웃
        </button>
      </form>
    </main>
  )
}
