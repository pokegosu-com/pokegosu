'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

/**
 * Typing the code in, for a machine whose screen you cannot click through —
 * a server over SSH, say. The link the machine prints lands on the same page
 * with the code already filled in.
 */
export function CodeForm() {
  const router = useRouter()
  const [code, setCode] = useState('')

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        // The server normalises what was typed, so anything goes from here.
        router.push(`/devices/add/${encodeURIComponent(code.trim())}`)
      }}
      className="flex items-center gap-2"
    >
      <input
        value={code}
        onChange={(e) => setCode(e.target.value)}
        required
        aria-label="코드"
        placeholder="XPTQ-4F2K"
        className="border-line-strong w-44 min-w-0 rounded-md border px-3 py-2 text-center font-mono text-sm tracking-[0.15em] uppercase"
      />
      <button
        type="submit"
        className="bg-accent text-surface flex-none rounded-md px-4 py-2 text-sm font-medium"
      >
        확인
      </button>
    </form>
  )
}
