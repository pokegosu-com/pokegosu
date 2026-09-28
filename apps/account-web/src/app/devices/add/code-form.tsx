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
      // The box, not the bare input, is what reads as the field, so it takes the
      // focus ring.
      className="border-line-strong has-[input:focus]:outline-accent flex items-center gap-2 rounded-md border py-[7px] pr-[7px] pl-3 has-[input:focus]:outline-2 has-[input:focus]:outline-offset-2"
    >
      <input
        value={code}
        onChange={(e) => setCode(e.target.value)}
        required
        aria-label="코드"
        placeholder="XPTQ-4F2K"
        className="min-w-0 flex-1 bg-transparent font-mono text-[13px] tracking-[0.15em] uppercase outline-none"
      />
      <button
        type="submit"
        className="border-accent bg-accent text-surface flex-none rounded-md border px-3 py-1.5 text-xs font-medium"
      >
        확인
      </button>
    </form>
  )
}
