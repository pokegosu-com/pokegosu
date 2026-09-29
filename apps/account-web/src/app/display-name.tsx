'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

/**
 * The name at the top of the account page, changed where it stands. Onboarding
 * called it changeable later; this is later. The handle beside it is not.
 */
export function DisplayName({ userId, displayName }: { userId: string; displayName: string }) {
  const router = useRouter()
  const [editing, setEditing] = useState(false)
  const [name, setName] = useState(displayName)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setSaving(true)
    setError(null)
    // Cleared, the database names them after the handle again.
    const { error: saveError } = await createClient()
      .from('profiles')
      .update({ display_name: name.trim() || null })
      .eq('id', userId)
    setSaving(false)
    if (saveError) {
      setError(saveError.message)
      return
    }
    setEditing(false)
    router.refresh()
  }

  if (!editing) {
    return (
      <div className="flex items-center gap-1">
        <h1 className="text-2xl font-semibold tracking-tight">{displayName}</h1>
        <button
          type="button"
          aria-label="이름 변경"
          title="이름 변경"
          onClick={() => setEditing(true)}
          className="text-muted hover:text-ink hover:bg-surface-raised grid size-8 place-items-center rounded-md"
        >
          <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true">
            <path
              d="M10.5 2.5l3 3L6 13H3v-3z"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.5"
              strokeLinejoin="round"
            />
          </svg>
        </button>
      </div>
    )
  }

  return (
    <form onSubmit={save} className="space-y-2">
      <div className="flex items-center gap-2">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={100}
          autoFocus
          aria-label="이름"
          className="border-line-strong rounded-md border px-3 py-1.5 text-lg"
        />
        <button type="submit" disabled={saving} className="text-accent text-sm disabled:opacity-50">
          저장
        </button>
        <button
          type="button"
          onClick={() => {
            setName(displayName)
            setEditing(false)
          }}
          className="text-muted text-sm"
        >
          취소
        </button>
      </div>
      {error && <p className="text-danger text-sm">{error}</p>}
    </form>
  )
}
