import { redirect } from 'next/navigation'

import { safeReturnTo } from '@/lib/return-to'
import { createClient } from '@/lib/supabase/server'

import { OnboardingForm } from './onboarding-form'

export default async function OnboardingPage({ searchParams }: PageProps<'/onboarding'>) {
  const params = await searchParams
  // The page in another app they were on when it sent them here.
  const returnTo = safeReturnTo(typeof params.next === 'string' ? params.next : null)

  const supabase = await createClient()
  const {
    data: { user },
  } = await supabase.auth.getUser()

  if (!user) redirect('/login')

  const { data: profile } = await supabase
    .from('profiles')
    .select('username')
    .eq('id', user.id)
    .single()

  if (profile?.username) redirect(returnTo ?? '/')

  return (
    <main className="mx-auto flex w-full max-w-task flex-1 flex-col justify-center gap-6 px-6 py-24">
      <div className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">계정 설정</h1>
        <p className="text-muted text-sm">{user.email}</p>
      </div>

      <OnboardingForm userId={user.id} returnTo={returnTo} />
    </main>
  )
}
