'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'

import { createClient } from '@pokegosu/supabase/client'

/** The database rejects three different things; each deserves its own sentence. */
function messageFor(code: string | undefined, fallback: string) {
  switch (code) {
    case '23514':
      return '소문자·숫자와 - _ 만, 3~30자로 지어주세요.'
    case '23505':
      return '이미 사용 중인 핸들입니다.'
    case 'P0001':
      return '핸들은 변경할 수 없습니다.'
    default:
      return fallback
  }
}

export function OnboardingForm({ userId }: { userId: string }) {
  const router = useRouter()
  const [username, setUsername] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [confirming, setConfirming] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function save() {
    setSaving(true)
    setError(null)

    const supabase = createClient()
    const { error: saveError } = await supabase
      .from('profiles')
      .update({ username, display_name: displayName || null })
      .eq('id', userId)

    if (saveError) {
      setError(messageFor(saveError.code, saveError.message))
      setConfirming(false)
      setSaving(false)
      return
    }

    router.replace('/')
    router.refresh()
  }

  if (confirming) {
    return (
      <div className="space-y-4">
        <p className="border-line-strong rounded-md border px-4 py-3 text-sm">
          핸들을 <strong>@{username}</strong> 으로 정합니다.
          <br />
          <span className="text-muted">한 번 정하면 변경할 수 없습니다.</span>
        </p>

        {error && <p className="text-sm text-danger">{error}</p>}

        <div className="flex gap-2">
          <button
            onClick={save}
            disabled={saving}
            className="bg-accent text-surface rounded-md px-4 py-2 text-sm font-medium disabled:opacity-50"
          >
            {saving ? '저장 중…' : '확정'}
          </button>
          <button
            onClick={() => setConfirming(false)}
            disabled={saving}
            className="border-line-strong rounded-md border px-4 py-2 text-sm"
          >
            뒤로
          </button>
        </div>
      </div>
    )
  }

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        setConfirming(true)
      }}
      className="space-y-3"
    >
      <label className="block space-y-1">
        <span className="text-muted text-sm">핸들 · 변경 불가</span>
        <input
          required
          value={username}
          onChange={(e) => setUsername(e.target.value)}
          pattern="[a-z0-9_-]{3,30}"
          placeholder="alice-gosu"
          className="border-line-strong w-full rounded-md border px-3 py-2 text-sm"
        />
      </label>

      <label className="block space-y-1">
        <span className="text-muted text-sm">표시 이름 · 나중에 변경 가능</span>
        <input
          value={displayName}
          onChange={(e) => setDisplayName(e.target.value)}
          placeholder="앨리스"
          className="border-line-strong w-full rounded-md border px-3 py-2 text-sm"
        />
      </label>

      {error && <p className="text-sm text-danger">{error}</p>}

      <button
        type="submit"
        className="bg-accent text-surface w-full rounded-md px-4 py-2 text-sm font-medium"
      >
        다음
      </button>
    </form>
  )
}
