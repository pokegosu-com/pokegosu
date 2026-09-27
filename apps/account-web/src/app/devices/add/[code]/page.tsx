import Link from 'next/link'

import { createClient } from '@/lib/supabase/server'
import { When } from '@/lib/when'

import { ApproveForm } from './approve-form'

/** What the machine asked, as the database describes it. */
type Pending =
  { outcome: 'pending'; device_name: string; requested_at: string } | { outcome: 'not_found' }

export default async function ApprovePage({ params }: PageProps<'/devices/add/[code]'>) {
  const { code } = await params
  const supabase = await createClient()

  // Read before approving: a person should see which machine they are letting
  // in, and nothing happens until they say so.
  const { data, error } = await supabase.rpc('pending_enrollment', { code })
  const pending = data as Pending | null

  return (
    <main className="mx-auto flex w-full max-w-sm flex-1 flex-col justify-center gap-6 px-6 py-24">
      <div className="space-y-1">
        <h1 className="text-2xl font-semibold tracking-tight">기기 추가</h1>
        <p className="text-muted font-mono text-sm tracking-[0.2em]">{decodeURIComponent(code)}</p>
      </div>

      {error && (
        <p className="rounded-md bg-danger-surface px-3 py-2 text-sm text-danger">
          {error.message}
        </p>
      )}

      {pending?.outcome === 'pending' ? (
        <>
          <dl className="border-line divide-line divide-y rounded-lg border text-sm">
            <div className="flex justify-between gap-4 px-4 py-3">
              <dt className="text-muted">기기</dt>
              <dd className="font-medium">{pending.device_name}</dd>
            </div>
            <div className="flex justify-between gap-4 px-4 py-3">
              <dt className="text-muted">요청</dt>
              <dd>
                <When at={pending.requested_at} />
              </dd>
            </div>
          </dl>

          <p className="text-muted text-xs">
            이 코드가 그 기기의 화면에 떠 있는 코드와 같은지 확인하세요. 승인하면 그 기기는 자기
            키를 받아 이 계정의 사용량을 올리게 됩니다.
          </p>

          <ApproveForm code={code} deviceName={pending.device_name} />
        </>
      ) : (
        !error && (
          <div className="space-y-3 text-sm">
            <p>기다리고 있는 요청이 없습니다. 코드가 만료되었거나 이미 승인되었습니다.</p>
            <p className="text-muted">
              기기에서 <code>pokegosu auth login</code> 을 다시 실행하면 새 코드가 나옵니다.
            </p>
            <Link href="/devices/add" className="text-accent underline">
              코드 다시 입력
            </Link>
          </div>
        )
      )}
    </main>
  )
}
