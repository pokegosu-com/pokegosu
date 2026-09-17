'use client'

import { useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

type Status = { kind: 'idle' | 'sending' | 'sent' | 'error'; message?: string }

export function LoginForm() {
  const [email, setEmail] = useState('')
  const [status, setStatus] = useState<Status>({ kind: 'idle' })

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setStatus({ kind: 'sending' })

    const supabase = createClient()
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: new URL('/auth/callback', window.location.origin).toString() },
    })

    setStatus(error ? { kind: 'error', message: error.message } : { kind: 'sent' })
  }

  if (status.kind === 'sent') {
    return (
      <p className="text-sm">
        <strong>{email}</strong> 으로 로그인 링크를 보냈습니다. 메일함을 확인하세요.
      </p>
    )
  }

  return (
    <form onSubmit={onSubmit} className="space-y-3">
      <label className="block space-y-1">
        <span className="text-muted text-sm">이메일</span>
        <input
          type="email"
          required
          autoComplete="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
          className="border-muted/40 w-full rounded-md border px-3 py-2 text-sm"
        />
      </label>

      <button
        type="submit"
        disabled={status.kind === 'sending'}
        className="bg-accent text-surface w-full rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
      >
        {status.kind === 'sending' ? '보내는 중…' : '로그인 링크 받기'}
      </button>

      {status.kind === 'error' && <p className="text-sm text-red-600">{status.message}</p>}
    </form>
  )
}
