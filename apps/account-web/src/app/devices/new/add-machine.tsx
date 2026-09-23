'use client'

import { useEffect, useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

/**
 * What is shown here is a code, not a credential. The machine trades it for a
 * key of its own, which never appears on this screen — so there is nothing
 * here worth reading over a shoulder, and nothing to be careful with after.
 *
 * The code is worth little by design: it lives ten minutes, works once, and
 * asking for another retires it.
 */
/** origin is this app's own address, which is what the CLI is pointed at. */
export function AddMachine({ origin }: { origin: string }) {
  const [issued, setIssued] = useState<{ code: string; expiresAt: Date } | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [now, setNow] = useState(() => new Date())
  useEffect(() => {
    if (!issued) return
    const timer = setInterval(() => setNow(new Date()), 1000)
    return () => clearInterval(timer)
  }, [issued])

  async function ask() {
    setBusy(true)
    setError(null)
    const { data, error: rpcError } = await createClient().rpc('create_enrollment_code')
    setBusy(false)

    if (rpcError) {
      setError(rpcError.message)
      return
    }
    const answer = data as { code: string; expires_at: string }
    setIssued({ code: answer.code, expiresAt: new Date(answer.expires_at) })
    setNow(new Date())
  }

  const left = issued ? Math.max(0, issued.expiresAt.getTime() - now.getTime()) : 0
  const expired = issued !== null && left === 0

  return (
    <div className="space-y-6">
      <pre className="bg-muted/10 overflow-x-auto rounded-md px-4 py-3 text-sm">
        pokegosu login --url {origin}
      </pre>

      {issued && !expired && (
        <div className="space-y-2 text-center">
          <p className="font-mono text-4xl font-semibold tracking-[0.2em]">{issued.code}</p>
          <p className="text-muted text-sm tabular-nums">
            {Math.floor(left / 60000)}:{String(Math.floor((left % 60000) / 1000)).padStart(2, '0')}{' '}
            뒤에 만료됩니다 · 한 번만 쓸 수 있습니다
          </p>
        </div>
      )}

      {expired && <p className="text-muted text-center text-sm">코드가 만료되었습니다.</p>}

      <button
        onClick={ask}
        disabled={busy}
        className="bg-accent text-surface w-full rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
      >
        {busy ? '받는 중…' : issued ? '새 코드 받기' : '코드 받기'}
      </button>

      {issued && !expired && (
        <p className="text-muted text-xs">새 코드를 받으면 지금 코드는 더 이상 쓸 수 없습니다.</p>
      )}

      {error && <p className="text-sm text-red-600">{error}</p>}
    </div>
  )
}
