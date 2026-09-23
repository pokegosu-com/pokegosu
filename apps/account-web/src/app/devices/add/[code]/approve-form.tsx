'use client'

import Link from 'next/link'
import { useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

type Approval = { outcome: 'approved'; device_name: string } | { outcome: 'not_found' }

/**
 * Approving is a button, never a link: a request must not be granted by
 * someone following a URL they were sent. What is approved is shown above it.
 */
export function ApproveForm({ code, deviceName }: { code: string; deviceName: string }) {
  const [approved, setApproved] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function approve() {
    setBusy(true)
    setError(null)

    const { data, error: rpcError } = await createClient().rpc('approve_enrollment', { code })
    setBusy(false)

    if (rpcError) {
      setError(rpcError.message)
      return
    }
    if ((data as Approval).outcome !== 'approved') {
      setError('이 요청은 더 이상 기다리고 있지 않습니다. 기기에서 다시 시작하세요.')
      return
    }
    setApproved(true)
  }

  if (approved) {
    return (
      <div className="space-y-3 text-sm">
        <p>
          <strong>{deviceName}</strong> 을(를) 승인했습니다. 기기의 터미널로 돌아가세요. 키는 그
          기기가 직접 받아 갑니다.
        </p>
        <Link href="/devices" className="text-accent underline">
          기기 목록
        </Link>
      </div>
    )
  }

  return (
    <div className="space-y-2">
      <button
        onClick={approve}
        disabled={busy}
        className="bg-accent text-surface w-full rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
      >
        {busy ? '승인하는 중…' : '승인'}
      </button>
      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  )
}
