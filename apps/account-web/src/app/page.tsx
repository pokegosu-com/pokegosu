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
    <main className="mx-auto flex w-full max-w-xl flex-1 flex-col justify-center gap-8 px-6 py-24">
      <div className="space-y-1">
        <DisplayName
          userId={user.id}
          displayName={profile.display_name}
          username={profile.username}
        />
        <p className="text-muted text-sm">@{profile.username}</p>
      </div>

      <dl className="border-muted/25 divide-muted/25 divide-y rounded-lg border text-sm">
        <div className="flex justify-between gap-4 px-4 py-3">
          <dt className="text-muted">이메일</dt>
          <dd>{user.email}</dd>
        </div>
        <div className="flex justify-between gap-4 px-4 py-3">
          <dt className="text-muted">가입일</dt>
          <dd>{new Date(user.created_at).toLocaleDateString('ko-KR')}</dd>
        </div>
      </dl>

      <form action="/auth/signout" method="post">
        <button
          type="submit"
          className="border-muted/40 rounded-md border px-4 py-2 text-sm font-medium"
        >
          로그아웃
        </button>
      </form>
    </main>
  )
}
